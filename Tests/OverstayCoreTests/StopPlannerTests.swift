import Foundation
import XCTest
@testable import OverstayCore

final class StopPlannerTests: XCTestCase {
    private func result(_ extra: [ProcessSnapshot], prefs: Preferences = .default) -> (ScanResult, World) {
        let raw = Fx.raw(extra)
        return (Scan.analyze(raw, prefs: prefs, now: Fx.now), Scan.world(raw))
    }

    private func bulk(_ extra: [ProcessSnapshot], prefs: Preferences = .default) -> StopPlan {
        let (r, w) = result(extra, prefs: prefs)
        return StopPlanner.plan(.ghosts(groupIDs: r.groups.map(\.id)), in: r, world: w, prefs: prefs, now: Fx.now, batchID: "b")
    }

    // MARK: plan

    func testBulkPlanHoldsGhostsOnlyNeverMaybes() {
        let plan = bulk([Fx.mcp(500), Fx.mcp(501, age: 30), Fx.mcp(502, stdin: .writerAlive)])
        XCTAssertEqual(plan.targets.map(\.identity.pid), [500])
        XCTAssertEqual(plan.targets[0].approvedTier, .ghost)
        XCTAssertEqual(plan.mode, .terminate)
        XCTAssertEqual(plan.graceSeconds, 5)
        XCTAssertEqual(plan.batchID, "b")
        XCTAssertEqual(plan.targets[0].projectName, "foo")
        XCTAssertEqual(plan.targets[0].signatureID, "mcp-server-named")
        XCTAssertEqual(plan.totalFootprintBytes, 50 << 20)
    }

    func testOnlyTheSelectedGroupsAreIncluded() {
        let (r, w) = result([Fx.mcp(500), Fx.mcp(510, cwd: "/Users/jane/dev/bar", root: "/Users/jane/dev/bar")])
        let bar = r.groups.first { $0.project?.name == "bar" }!
        let plan = StopPlanner.plan(.ghosts(groupIDs: [bar.id]), in: r, world: w, prefs: .default, now: Fx.now, batchID: "b")
        XCTAssertEqual(plan.targets.map(\.identity.pid), [510])
        XCTAssertEqual(plan.groupIDs, [bar.id])
        XCTAssertTrue(StopPlanner.plan(.ghosts(groupIDs: ["nope"]), in: r, world: w, prefs: .default, now: Fx.now, batchID: "b").targets.isEmpty)
    }

    func testOrderIsLeafFirstThenNewestThenHighestPid() {
        let wrapper = Fx.proc(500, path: "/bin/sh", argv: ["sh", "-c", "mcp-server-time /Users/jane/dev/foo"], age: 300_000)
        let mid = Fx.mcp(510, tag: "time", ppid: 500, age: 250_000)
        let leafOld = Fx.mcp(520, tag: "time", ppid: 510, age: 240_000)
        let leafNew = Fx.mcp(521, tag: "time", ppid: 510, age: 100_000)
        let sibling = Fx.mcp(600, age: 500_000)
        let plan = bulk([wrapper, mid, leafOld, leafNew, sibling])
        XCTAssertEqual(plan.targets.map(\.depth), [2, 2, 1, 0, 0])
        XCTAssertEqual(plan.targets.map(\.identity.pid), [521, 520, 510, 500, 600], "depth, then newest, then pid")
    }

    func testProtectedMembersAreSkippedWithAReason() {
        // Hand-built group containing things that must never be signalled: an ancestor, pid 1, ourselves, another user's process.
        let (_, w) = result([])
        func ghost(_ p: ProcessSnapshot) -> ClassifiedProcess {
            ClassifiedProcess(process: p, tier: .ghost, agent: .unattributed,
                              evidence: SignalEvidence(orphaned: true, signatureID: "mcp-server-named", ageGateMet: true), why: "forced")
        }
        let bad = [w.byPid[850]!, w.byPid[Fx.selfPid]!, Fx.proc(1, ppid: 0, path: "/sbin/launchd"), Fx.mcp(77).with(uid: 502),
                   Fx.proc(78, path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", argv: ["Finder"])]
        let group = LeftoverGroup(id: "g", agent: .unattributed, project: nil, processes: bad.map(ghost) + [ghost(Fx.mcp(500))])
        let scan = ScanResult(scannedAt: Fx.now, groups: [group], examinedCount: 1)
        let w2 = Fx.world([Fx.mcp(500)])
        let plan = StopPlanner.plan(.ghosts(groupIDs: ["g"]), in: scan, world: w2, prefs: .default, now: Fx.now, batchID: "b")
        XCTAssertEqual(plan.targets.map(\.identity.pid), [500])
        XCTAssertEqual(Set(plan.skipped.map(\.pid)), [850, Fx.selfPid, 1, 77, 78])
        XCTAssertTrue(plan.skipped.allSatisfy { $0.reason.hasPrefix("protected: ") })
    }

    func testAMemberThatChangedSinceTheScanIsDroppedAtPlanTime() {
        let (r, _) = result([Fx.mcp(500)])
        // Same scan, but now a live session exists in the project: the Ghost is a Maybe in the fresh world.
        let w = Fx.world([Fx.mcp(500), Fx.claude(400)])
        let plan = StopPlanner.plan(.ghosts(groupIDs: r.groups.map(\.id)), in: r, world: w, prefs: .default, now: Fx.now, batchID: "b")
        XCTAssertTrue(plan.targets.isEmpty)
        XCTAssertEqual(plan.skipped.map(\.pid), [500])
        XCTAssertEqual(plan.skipped.first?.reason, "changed since the scan")
    }

    func testNeverTouchAddedAfterTheScanStillProtects() {
        let (r, w) = result([Fx.mcp(500)])
        let prefs = Preferences(neverTouch: ["node"])
        let plan = StopPlanner.plan(.ghosts(groupIDs: r.groups.map(\.id)), in: r, world: w, prefs: prefs, now: Fx.now, batchID: "b")
        XCTAssertTrue(plan.targets.isEmpty)
        XCTAssertEqual(plan.skipped.count, 1)
    }

    func testSingleMaybeNeedsItsOwnConfirmationWhenYoung() {
        let young = Fx.mcp(500, age: 3600)
        let (r, w) = result([young, Fx.claude(400)])
        let tooSoon = StopPlanner.plan(.single(pid: 500, confirmedYoung: false), in: r, world: w, prefs: .default, now: Fx.now, batchID: "b")
        XCTAssertTrue(tooSoon.targets.isEmpty)
        XCTAssertEqual(tooSoon.skipped.first?.pid, 500)
        let ok = StopPlanner.plan(.single(pid: 500, confirmedYoung: true), in: r, world: w, prefs: .default, now: Fx.now, batchID: "b")
        XCTAssertEqual(ok.targets.map(\.identity.pid), [500])
        XCTAssertEqual(ok.targets[0].approvedTier, .maybe)
        XCTAssertEqual(ok.targets[0].depth, 0)
        // Old Maybes need no extra tick; unknown pids and non-listed pids produce an empty plan.
        let (r2, w2) = result([Fx.mcp(501, age: 30 * 3600), Fx.claude(400)])
        XCTAssertEqual(StopPlanner.plan(.single(pid: 501, confirmedYoung: false), in: r2, world: w2, prefs: .default, now: Fx.now, batchID: "b").targets.count, 1)
        XCTAssertTrue(StopPlanner.plan(.single(pid: 400, confirmedYoung: true), in: r2, world: w2, prefs: .default, now: Fx.now, batchID: "b").targets.isEmpty)
        XCTAssertTrue(StopPlanner.plan(.single(pid: 99999, confirmedYoung: true), in: r2, world: w2, prefs: .default, now: Fx.now, batchID: "b").targets.isEmpty)
    }

    func testBulkNeverIncludesAMaybeEvenIfItsGroupIsSelected() {
        let (r, w) = result([Fx.mcp(500, age: 30)])
        let plan = StopPlanner.plan(.ghosts(groupIDs: r.groups.map(\.id)), in: r, world: w, prefs: .default, now: Fx.now, batchID: "b")
        XCTAssertTrue(plan.targets.isEmpty)
    }

    // MARK: force plan

    func testForcePlanIsBuiltOnlyFromSurvivors() {
        let plan = bulk([Fx.mcp(500), Fx.mcp(501)])
        let results = [TargetOutcome(target: plan.targets[0], status: .stopped),
                       TargetOutcome(target: plan.targets[1], status: .survived)]
        let outcome = StopOutcome(batchID: "b", mode: .terminate, startedAt: Fx.now, finishedAt: Fx.now, results: results)
        let force = StopPlanner.forcePlan(from: outcome, batchID: "f")
        XCTAssertEqual(force.mode, .force)
        XCTAssertEqual(force.graceSeconds, 2)
        XCTAssertEqual(force.targets.map(\.identity), [plan.targets[1].identity])
        XCTAssertEqual(force.batchID, "f")
        let none = StopOutcome(batchID: "b", mode: .terminate, startedAt: Fx.now, finishedAt: Fx.now,
                               results: [TargetOutcome(target: plan.targets[0], status: .alreadyGone)])
        XCTAssertTrue(StopPlanner.forcePlan(from: none, batchID: "f").targets.isEmpty)
        // SIGKILL survivors are never planned for SIGKILL again.
        var again = outcome
        again.mode = .force
        XCTAssertFalse(again.survivors.isEmpty)
        XCTAssertTrue(StopPlanner.forcePlan(from: again, batchID: "f").targets.isEmpty)
    }

    // MARK: verify

    private func target(_ p: ProcessSnapshot, tier: Classification = .ghost, sig: String = "mcp-server-named") -> StopTarget {
        StopTarget(identity: p.identity, name: p.name, signatureID: sig, agent: .unattributed, projectName: "foo",
                   approvedTier: tier, footprintBytes: p.footprintBytes, depth: 0, why: "t")
    }

    private func verify(_ t: StopTarget, fresh: ProcessSnapshot?, extra: [ProcessSnapshot] = [], prefs: Preferences = .default) -> StopPlanner.Verification {
        StopPlanner.verify(t, fresh: fresh, world: Fx.world([fresh].compactMap { $0 } + extra), prefs: prefs, now: Fx.now)
    }

    func testVerifyAcceptsTheSameGhost() {
        let p = Fx.mcp(500)
        XCTAssertEqual(verify(target(p), fresh: p), .ok)
    }

    func testVerifyGoneWhenNotFound() {
        XCTAssertEqual(verify(target(Fx.mcp(500)), fresh: nil), .gone)
    }

    func testVerifyRejectsAReusedPid() {
        let p = Fx.mcp(500)
        var reused = p
        reused.startSeconds += 1
        guard case .changed = verify(target(p), fresh: reused) else { return XCTFail("start seconds differ") }
        reused = p
        reused.startMicroseconds += 1
        guard case .changed = verify(target(p), fresh: reused) else { return XCTFail("start microseconds differ") }
    }

    func testVerifyRejectsAnUnreadablePath() {
        let p = Fx.mcp(500)
        var q = p
        q.path = ""
        guard case .changed = verify(target(p), fresh: q) else { return XCTFail("empty path") }
        var blank = p
        blank.path = ""
        guard case .changed = verify(target(blank), fresh: blank) else { return XCTFail("empty path on both sides") }
    }

    func testVerifyRejectsAChangedPathOrUid() {
        let p = Fx.mcp(500)
        var q = p
        q.path = "/opt/homebrew/bin/node"
        guard case .changed = verify(target(p), fresh: q) else { return XCTFail("path differs") }
        q = p
        q.uid = 502
        guard case .blocked = verify(target(p), fresh: q) else { return XCTFail("another user is blocked, not signalled") }
        var t = target(p)
        t.identity.uid = 502
        guard case .blocked = verify(t, fresh: p) else { return XCTFail("a target of another user is blocked") }
    }

    func testVerifyRejectsAChangedSignature() {
        let p = Fx.mcp(500)
        guard case .changed = verify(target(p, sig: "playwright-mcp"), fresh: p) else { return XCTFail("signature differs") }
        var plain = p
        plain.argv = ["node", "server.js"]
        guard case .changed = verify(target(p), fresh: plain) else { return XCTFail("no longer matches any signature") }
    }

    func testVerifyRejectsAGhostThatBecameAMaybe() {
        let p = Fx.mcp(500)
        guard case .changed = verify(target(p), fresh: p, extra: [Fx.claude(400)]) else { return XCTFail("a live session appeared") }
        var alive = p
        alive.stdin = .writerAlive
        guard case .changed = verify(target(p), fresh: alive) else { return XCTFail("its input pipe is held again") }
        // ...but a confirmed Maybe may still be a Maybe (or a Ghost) afterwards.
        XCTAssertEqual(verify(target(p, tier: .maybe), fresh: p, extra: [Fx.claude(400)]), .ok)
        XCTAssertEqual(verify(target(p, tier: .maybe), fresh: p), .ok)
    }

    func testVerifyRejectsAParentThatCameBack() {
        let p = Fx.mcp(500)
        var adopted = p
        adopted.ppid = 850
        guard case .changed = verify(target(p), fresh: adopted, extra: []) else { return XCTFail("no longer orphaned") }
    }

    func testVerifyBlocksPidOneSelfAndAncestors() {
        let launchd = Fx.proc(1, ppid: 0, path: "/sbin/launchd")
        XCTAssertEqual(verify(target(launchd), fresh: launchd), .blocked("a core macOS process"))
        let me = Fx.world([]).byPid[Fx.selfPid]!
        guard case .blocked = verify(target(me), fresh: me) else { return XCTFail("self") }
        let shell = Fx.world([]).byPid[850]!
        guard case .blocked = verify(target(shell), fresh: shell) else { return XCTFail("ancestor") }
        // Guards run before the lookup: a vanished ancestor is still "blocked", never "gone".
        guard case .blocked = verify(target(shell), fresh: nil) else { return XCTFail("ancestor, vanished") }
        let zero = Fx.proc(0, ppid: 0, path: "/kernel")
        guard case .blocked = verify(target(zero), fresh: nil) else { return XCTFail("pid 0") }
    }

    func testVerifyBlocksAFreshProcessThatIsProtectedNow() {
        let p = Fx.mcp(500)
        guard case .blocked = verify(target(p), fresh: p, prefs: Preferences(neverTouch: ["node"])) else { return XCTFail("never-touch") }
        let tty = p.with(tty: 1, sid: 850)
        guard case .blocked = verify(target(p), fresh: tty) else { return XCTFail("attached to a live terminal session now") }
    }

    func testVerifyRejectsATargetThatBecameAnAgentSession() {
        var p = Fx.mcp(500)
        let t = target(p)
        p.argv = ["node", "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"]
        guard case .blocked = verify(t, fresh: p) else { return XCTFail("agent session") }
    }
}
