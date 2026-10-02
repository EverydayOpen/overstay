import Darwin
import Foundation
import OverstayCore

/// The whole signal path, and the only file in the code base that contains `kill(`, a `SIG` name or a process-group call
/// (BUILD_PLAN §3 rules 1, 4, 6, 7; CI enforces it). Only the two signals below are expressible, only for a validated
/// pid above 1, only to one process at a time, only after the process was re-read and re-verified in the same
/// synchronous stretch of code.
enum Signaller {
    private enum Kind { case term, kill }

    /// Runs a plan, never throws. Per depth wave, deepest first: take a fresh scan, then for each target re-read its pid,
    /// verify, guard and send with no `await` in between; then poll up to `plan.graceSeconds` for the wave to exit.
    /// The grace is per wave (depth level), not per stop: a tree of SIGTERM-proof levels can take graceSeconds x levels.
    /// Every outcome goes to `progress` and `log` as it is produced, and each signal is preceded by its own `.signalled`
    /// line. `log` returns false when a line could not be written, after which nothing more is signalled (fail closed). `.terminate` plans can never reach SIGKILL.
    /// Call it with argument labels, not a trailing closure: `log` is deliberately last and defaulted.
    static func run(_ plan: StopPlan, prefs: Preferences, now: @Sendable () -> Date,
                    progress: @Sendable (TargetOutcome) -> Void,
                    log: @Sendable (ActivityEntry) -> Bool = { ActivityStore.append($0) }) async -> StopOutcome {
        let startedAt = now()
        let kind: Kind = plan.mode == .force ? .kill : .term
        let me = getpid()
        let parent = getppid()
        var results: [TargetOutcome] = []
        var logOK = true

        func record(_ o: TargetOutcome) {
            results.append(o)
            progress(o)
            if !log(ActivityEntry(o, batchID: plan.batchID, mode: plan.mode, at: now())) { logOK = false }
        }
        // What the user saw skipped is part of the audit trail too.
        for s in plan.skipped {
            let e = ActivityEntry(timestamp: now(), batchID: plan.batchID, mode: plan.mode, pid: s.pid, executable: s.name,
                                  signatureID: "", agent: .unattributed, project: nil, footprintBytes: 0,
                                  result: .blocked, errno: nil, why: s.reason)
            if !log(e) { logOK = false }
        }

        for depth in Set(plan.targets.map(\.depth)).sorted(by: >) {
            let world = Scan.world(ProcessScanner.scan(now: now()))
            let ancestors = ownAncestors(from: parent)   // walked here, independently of Core's own list
            var pending: [StopTarget] = []

            for t in plan.targets where t.depth == depth {
                let pid = t.identity.pid
                func settle(_ status: TargetStatus, _ detail: String? = nil, errno e: Int32? = nil) {
                    record(TargetOutcome(target: t, status: status, errno: e, detail: detail))
                }
                guard logOK else { settle(.blocked, "Activity log is not writable"); continue }
                guard pid > 1, pid != me, pid != parent, !ancestors.contains(pid), !world.ancestors.contains(pid),
                      t.identity.uid == getuid() else {
                    settle(.blocked, "Overstay never signals this process")
                    continue
                }
                // Re-read, verify, guard, send: synchronous, nothing may suspend between these lines.
                let fresh = ProcessScanner.snapshot(pid: pid)
                switch StopPlanner.verify(t, fresh: fresh, world: world, prefs: prefs, now: now()) {
                case .ok: break
                case .gone: settle(.alreadyGone); continue
                case .changed(let why): settle(.changedSinceScan, why); continue
                case .blocked(let why): settle(.blocked, why); continue
                }
                // Our own identity check as well, in case verify ever regresses: same pid, start time, path, uid.
                guard let f = fresh, f.identity == t.identity, f.uid == getuid() else {
                    settle(.changedSinceScan, "Changed since the scan")
                    continue
                }
                // Write-ahead: the log line exists before the signal does, and no line means no signal.
                guard log(ActivityEntry(TargetOutcome(target: t, status: .signalled), batchID: plan.batchID, mode: plan.mode, at: now())) else {
                    logOK = false
                    settle(.blocked, "Activity log is not writable")
                    continue
                }
                switch send(kind, to: pid) {
                case 0: pending.append(t)
                case let e where e == ESRCH: settle(.alreadyGone, errno: e)
                case let e where e == EPERM: settle(.refused, errno: e)
                case let e: settle(.failed, errno: e)
                }
            }

            // Grace period, per wave so shallower parents still get their full wait: a target has exited when its pid is gone (or a zombie) or is now a different process.
            let deadline = Date().addingTimeInterval(plan.graceSeconds)
            while !pending.isEmpty {
                pending = pending.filter { (t: StopTarget) -> Bool in
                    if let s = ProcessScanner.snapshot(pid: t.identity.pid), s.identity == t.identity { return true }
                    record(TargetOutcome(target: t, status: plan.mode == .force ? .forceStopped : .stopped))
                    return false
                }
                if pending.isEmpty || Date() >= deadline || Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            for t in pending { record(TargetOutcome(target: t, status: .survived)) }
        }
        return StopOutcome(batchID: plan.batchID, mode: plan.mode, startedAt: startedAt, finishedAt: now(),
                           results: results, skipped: plan.skipped)
    }

    /// Our parent chain up to (excluding) pid 1, loop-safe, at most 64 steps. These are never signalled.
    private static func ownAncestors(from parent: Int32) -> Set<Int32> {
        var chain = Set<Int32>()
        var p = parent
        while p > 1, chain.count < 64, chain.insert(p).inserted, let up = ProcessScanner.ppid(of: p) { p = up }
        return chain
    }

    /// The ONLY call to kill(2) in the code base. SIGTERM for `.term`, SIGKILL for `.kill`; no other signal number is
    /// expressible and the target is always one positive pid above 1 that is not us. Returns 0 or errno.
    private static func send(_ kind: Kind, to pid: Int32) -> Int32 {
        guard pid > 1, pid != getpid() else { return EINVAL }
        let number: Int32
        switch kind {
        case .term: number = SIGTERM
        case .kill: number = SIGKILL
        }
        return Darwin.kill(pid, number) == 0 ? 0 : errno
    }
}
