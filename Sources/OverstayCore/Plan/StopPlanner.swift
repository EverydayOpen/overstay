import Foundation

public enum StopPlanner {
    public enum Selection: Sendable {
        /// Bulk: the Ghost members of these groups, nothing else.
        case ghosts(groupIDs: [String])
        /// One Maybe (or Ghost) the user picked; `confirmedYoung` is the extra tick for young Maybes.
        case single(pid: Int32, confirmedYoung: Bool)
    }

    /// Never includes protected, ancestors, self, pid <= 1, other users or Maybes in bulk; anything dropped goes to
    /// `skipped` with a reason. Order is leaf-first: depth (within the selected set, following ppid) descending, then
    /// start time newest first, then pid descending.
    public static func plan(_ selection: Selection, in result: ScanResult, world: World, prefs: Preferences,
                            now: Date, batchID: String) -> StopPlan {
        var chosen: [ClassifiedProcess] = []
        var skipped: [SkippedTarget] = []
        var groupIDs: [String] = []
        switch selection {
        case .ghosts(let ids):
            for g in result.groups where ids.contains(g.id) {
                groupIDs.append(g.id)
                chosen += g.ghosts
            }
        case .single(let pid, let confirmedYoung):
            for g in result.groups {
                guard let c = g.processes.first(where: { $0.process.pid == pid }) else { continue }
                groupIDs = [g.id]
                if Classifier.requiresYoungConfirmation(c, prefs: prefs, now: now), !confirmedYoung {
                    skipped.append(SkippedTarget(pid: pid, name: c.process.name,
                                                 reason: "started under \(prefs.confirmYoungerThanHours) hours ago and needs its own confirmation"))
                } else {
                    chosen = [c]
                }
                break
            }
        }

        var accepted: [ClassifiedProcess] = []
        var seen = Set<Int32>()
        for c in chosen where seen.insert(c.process.pid).inserted {
            if let reason = Protected.reason(for: c.process, in: world, prefs: prefs) {
                skipped.append(SkippedTarget(pid: c.process.pid, name: c.process.name, reason: "protected: \(reason)"))
            } else if c.evidence.signatureID == nil || !tierAllowed(c.tier, Classifier.classify(c.process, in: world, prefs: prefs, now: now).tier) {
                skipped.append(SkippedTarget(pid: c.process.pid, name: c.process.name, reason: "changed since the scan"))
            } else {
                accepted.append(c)
            }
        }

        let parent = Dictionary(accepted.map { ($0.process.pid, $0.process.ppid) }, uniquingKeysWith: { a, _ in a })
        let targets = accepted.map { c in
            StopTarget(identity: c.process.identity, name: c.process.name, signatureID: c.evidence.signatureID ?? "",
                       agent: c.agent,
                       projectName: ProjectNamer.project(projectRoot: c.process.projectRoot, cwd: c.process.cwd, home: world.home)?.name,
                       approvedTier: c.tier, footprintBytes: c.process.footprintBytes,
                       depth: Forest.depth(of: c.process.pid, parent: parent), why: c.why)
        }
        return StopPlan(batchID: batchID, mode: .terminate, groupIDs: groupIDs, targets: leafFirst(targets),
                        skipped: skipped, graceSeconds: 5)
    }

    /// mode .force, grace 2 s, built only from the survivors of a `.terminate` outcome (SIGKILL is never re-planned from
    /// SIGKILL survivors); any other outcome gives an empty plan. The caller narrows to one group by filtering
    /// `outcome.results` first (a StopOutcome is plain data).
    public static func forcePlan(from outcome: StopOutcome, batchID: String) -> StopPlan {
        guard outcome.mode == .terminate else {
            return StopPlan(batchID: batchID, mode: .force, groupIDs: [], targets: [], graceSeconds: 2)
        }
        return StopPlan(batchID: batchID, mode: .force, groupIDs: [], targets: leafFirst(outcome.survivors), skipped: [], graceSeconds: 2)
    }

    public enum Verification: Equatable, Sendable {
        case ok
        /// No such process (or a zombie): `TargetStatus.alreadyGone`.
        case gone
        /// Identity, signature or tier differs: `TargetStatus.changedSinceScan`.
        case changed(String)
        /// Protected, ancestor, self, pid <= 1, other user: `TargetStatus.blocked`.
        case blocked(String)
    }

    /// Pure. `fresh` is the pid re-read just now (nil = not found); `world` comes from a scan taken for this stop.
    /// Checks, in order: guards on the pid and the target's user -> fresh != nil -> fresh user -> same identity (pid, start time, uid, path) -> protected
    /// list -> same signature -> tier still allowed by `target.approvedTier`. Anything but `.ok` means nothing is sent.
    public static func verify(_ target: StopTarget, fresh: ProcessSnapshot?, world: World, prefs: Preferences,
                              now: Date) -> Verification {
        let pid = target.identity.pid
        if pid <= 1 { return .blocked("a core macOS process") }
        if pid == world.selfPid { return .blocked("Overstay itself") }
        if world.ancestors.contains(pid) { return .blocked("it hosts this app (terminal, shell or editor)") }
        if target.identity.uid != world.uid { return .blocked("it belongs to another user") }
        guard let fresh else { return .gone }
        if fresh.uid != world.uid { return .blocked("it belongs to another user") }
        if fresh.path.isEmpty { return .changed("its executable path could not be read") }
        guard fresh.pid == pid, fresh.identity == target.identity else {
            return .changed("a different process now uses this id, or it was replaced")
        }
        if let r = Protected.reason(for: fresh, in: world, prefs: prefs) { return .blocked(r) }
        guard Signatures.match(fresh)?.id == target.signatureID else { return .changed("no longer matches what was scanned") }
        let tier = Classifier.classify(fresh, in: world, prefs: prefs, now: now).tier
        return tierAllowed(target.approvedTier, tier) ? .ok : .changed("now classified as \(tier.rawValue)")
    }

    /// A Ghost approval needs a Ghost now; a confirmed Maybe may be a Maybe or a Ghost now. Nothing else passes.
    private static func tierAllowed(_ approved: Classification, _ now: Classification) -> Bool {
        switch approved {
        case .ghost: return now == .ghost
        case .maybe: return now == .ghost || now == .maybe
        case .ignored, .protected: return false
        }
    }

    private static func leafFirst(_ targets: [StopTarget]) -> [StopTarget] {
        targets.sorted {
            if $0.depth != $1.depth { return $0.depth > $1.depth }
            let (a, b) = (($0.identity.startSeconds, $0.identity.startMicroseconds), ($1.identity.startSeconds, $1.identity.startMicroseconds))
            if a != b { return a > b }
            return $0.identity.pid > $1.identity.pid
        }
    }
}
