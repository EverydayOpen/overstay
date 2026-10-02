import Foundation

/// The demo implementation of `Backend` (BUILD_PLAN §9): serves a scenario's synthetic table and mutates an in-memory copy.
/// Nothing is read from or signalled to the real system and no file is written; the activity log lives in memory.
/// A stop re-verifies every target with the real `StopPlanner.verify` against that copy, like the live one does.
public enum DemoBackend {
    /// `seconds` is how long a whole stop takes (staggered per target, so the collapse animates); 0 for tests.
    /// `now` is the only clock: it stamps the table once and the log lines.
    public static func make(_ scenario: DemoScenario, seconds: Double = 1.2,
                            now: @escaping @Sendable () -> Date = { Date() }) -> Backend {
        let start = now()
        let state = DemoState(DemoScenarios.rawScan(scenario, now: start), log: DemoScenarios.history(for: scenario, now: start))
        return Backend(
            scan: { state.raw },
            stop: { plan, prefs, progress in
                await run(plan, prefs, progress, scenario: scenario, state: state, seconds: seconds, now: now)
            },
            loadLog: { state.log },
            isDemo: true)
    }

    private static func run(_ plan: StopPlan, _ prefs: Preferences, _ progress: @escaping @Sendable (TargetOutcome) -> Void,
                            scenario: DemoScenario, state: DemoState, seconds: Double,
                            now: @escaping @Sendable () -> Date) async -> StopOutcome {
        let startedAt = now()
        let raw = state.raw
        let world = Scan.world(raw)
        let pause = UInt64(max(seconds, 0) / Double(max(plan.targets.count, 1)) * 1_000_000_000)
        // What the user saw skipped is part of the audit trail too (as the live signaller does).
        for s in plan.skipped {
            state.append(ActivityEntry(timestamp: now(), batchID: plan.batchID, mode: plan.mode, pid: s.pid, executable: s.name,
                                       signatureID: "", agent: .unattributed, project: nil, footprintBytes: 0,
                                       result: .blocked, errno: nil, why: s.reason))
        }
        var results: [TargetOutcome] = []
        for target in plan.targets {   // already leaf-first
            if pause > 0 { try? await Task.sleep(nanoseconds: pause) }
            let outcome: TargetOutcome
            switch StopPlanner.verify(target, fresh: state.process(target.identity.pid), world: world, prefs: prefs, now: raw.scannedAt) {
            case .gone:
                outcome = TargetOutcome(target: target, status: .alreadyGone)
            case .changed(let why):
                outcome = TargetOutcome(target: target, status: .changedSinceScan, detail: why)
            case .blocked(let why):
                outcome = TargetOutcome(target: target, status: .blocked, detail: why)
            case .ok:
                let status = DemoScenarios.answer(scenario, for: target, mode: plan.mode)
                if status.wasStopped { state.remove(target.identity.pid) }
                outcome = TargetOutcome(target: target, status: status, errno: status == .refused ? 1 : nil)   // 1 = EPERM
            }
            results.append(outcome)
            state.append(ActivityEntry(outcome, batchID: plan.batchID, mode: plan.mode, at: now()))
            progress(outcome)
        }
        return StopOutcome(batchID: plan.batchID, mode: plan.mode, startedAt: startedAt, finishedAt: now(),
                           results: results, skipped: plan.skipped)
    }
}

/// The mutable copy behind one demo backend: the process table and the log.
final class DemoState: @unchecked Sendable {
    private let lock = NSLock()
    private var table: RawScan
    private var entries: [ActivityEntry]

    init(_ raw: RawScan, log: [ActivityEntry]) {
        table = raw
        entries = log
    }

    var raw: RawScan {
        lock.lock()
        defer { lock.unlock() }
        return table
    }

    var log: [ActivityEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func process(_ pid: Int32) -> ProcessSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return table.processes.first { $0.pid == pid }
    }

    func append(_ entry: ActivityEntry) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }

    /// An exited process; its remaining children are adopted by launchd, as the kernel does.
    func remove(_ pid: Int32) {
        lock.lock()
        defer { lock.unlock() }
        table.processes.removeAll { $0.pid == pid }
        for i in table.processes.indices where table.processes[i].ppid == pid { table.processes[i].ppid = 1 }
    }
}
