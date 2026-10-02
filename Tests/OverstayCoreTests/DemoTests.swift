import XCTest
@testable import OverstayCore

/// The demo scenarios (BUILD_PLAN §9, §6.1): the numbers the README, site and screenshots promise come out of the real
/// classifier, and the demo backend stops, refuses and survives the way each scenario says. Owner: demo.
final class DemoTests: XCTestCase {
    private let now = Fx.now
    private let prefs = Preferences.default

    private func analyze(_ s: DemoScenario) -> ScanResult {
        Scan.analyze(DemoScenarios.rawScan(s, now: now), prefs: prefs, now: now)
    }

    private func ghostGroups(_ r: ScanResult) -> [LeftoverGroup] { r.groups.filter { $0.ghostCount > 0 } }

    func testLeftoversAreTheFiveGroupsOfThePlan() {
        let r = analyze(.leftovers)
        XCTAssertEqual(r.ghostCount, 183)
        XCTAssertEqual(r.maybeCount, 4)
        XCTAssertEqual(Format.bytes(r.ghostBytes), "9.4 GB")
        let g = ghostGroups(r)
        XCTAssertEqual(g.count, 5)
        XCTAssertEqual(r.groups.count, 5, "the four Maybes sit inside the five groups")
        let rows = g.map { "\(Grouping.title($0)) \($0.project?.name ?? "-") \($0.ghostCount) \(Format.bytes($0.ghostBytes))" }
        XCTAssertEqual(Set(rows), ["Agent tool servers foo 61 3.1 GB", "Codex bar 40 2.2 GB", "Headless browsers - 12 1.4 GB",
                                   "Agent tool servers baz 38 1.5 GB", "Codex qux 32 1.2 GB"])
        XCTAssertEqual(g.map(\.ghostBytes), g.map(\.ghostBytes).sorted(by: >), "largest first")
        XCTAssertEqual(g.first?.project?.name, "foo")
    }

    func testStartedTextsMatchTheSite() {
        let r = analyze(.leftovers)
        func started(_ project: String?) -> String? {
            ghostGroups(r).first { $0.project?.name == project }?.oldestStart
                .map { Format.started(seconds: Int(now.timeIntervalSince($0))) }
        }
        XCTAssertEqual(started("foo"), "started 3 days ago")
        XCTAssertEqual(started("bar"), "started 2 days ago")
        XCTAssertEqual(started(nil), "started 5 hours ago")
    }

    func testEveryMaybeHasItsOwnReason() {
        let maybes = analyze(.leftovers).groups.flatMap(\.maybes)
        XCTAssertEqual(maybes.count, 4)
        XCTAssertTrue(maybes.contains { $0.evidence.networkServer })
        XCTAssertTrue(maybes.contains { !$0.evidence.ageGateMet })
        XCTAssertTrue(maybes.contains { $0.evidence.signatureStrength == .generic })
        XCTAssertTrue(maybes.contains { $0.evidence.stdin == .writerAlive })
    }

    func testQuietAndFirstRunHaveNothingToList() {
        for s in [DemoScenario.quiet, .firstRun] {
            let r = analyze(s)
            XCTAssertTrue(r.isQuiet, s.rawValue)
            XCTAssertGreaterThan(r.examinedCount, 200)
            XCTAssertEqual(r.unreadableCount, 0)
        }
    }

    func testMaybeOnlyHasSixMaybesAndNoGhost() {
        let r = analyze(.maybeOnly)
        XCTAssertEqual(r.ghostCount, 0)
        XCTAssertEqual(r.maybeCount, 6)
        XCTAssertTrue(r.groups.flatMap(\.maybes).contains { !$0.evidence.liveSessionPids.isEmpty }, "one has a live session")
    }

    func testRefusedAndSurvivorsStartLikeLeftovers() {
        let base = DemoScenarios.rawScan(.leftovers, now: now)
        XCTAssertEqual(DemoScenarios.rawScan(.refused, now: now), base)
        XCTAssertEqual(DemoScenarios.rawScan(.survivors, now: now), base)
    }

    func testDeterministicAndRelativeToNow() {
        XCTAssertEqual(DemoScenarios.rawScan(.leftovers, now: now), DemoScenarios.rawScan(.leftovers, now: now))
        let later = now.addingTimeInterval(86_400)
        let a = analyze(.leftovers)
        let b = Scan.analyze(DemoScenarios.rawScan(.leftovers, now: later), prefs: prefs, now: later)
        XCTAssertEqual(a.ghostCount, b.ghostCount)
        XCTAssertEqual(a.ghostBytes, b.ghostBytes)
    }

    func testTheTableHoldsNothingPersonal() {
        for s in DemoScenario.allCases {
            for p in DemoScenarios.rawScan(s, now: now).processes {
                XCTAssertTrue(p.envMarkers.isEmpty)
                for text in [p.path, p.cwd ?? "", p.projectRoot ?? ""] + p.argv where text.contains("/Users/") {
                    XCTAssertTrue(text.contains("/Users/jane"), text)
                }
            }
        }
    }

    func testBulkPlanTakesEveryGhostLeafFirstAndNothingElse() {
        let raw = DemoScenarios.rawScan(.leftovers, now: now)
        let r = Scan.analyze(raw, prefs: prefs, now: now)
        let plan = StopPlanner.plan(.ghosts(groupIDs: r.groups.map(\.id)), in: r, world: Scan.world(raw), prefs: prefs, now: now, batchID: "t")
        XCTAssertEqual(plan.targets.count, 183)
        XCTAssertTrue(plan.skipped.isEmpty)
        XCTAssertTrue(plan.targets.allSatisfy { $0.approvedTier == .ghost })
        XCTAssertEqual(plan.targets.map(\.depth), plan.targets.map(\.depth).sorted(by: >))
        XCTAssertGreaterThan(plan.targets.first?.depth ?? 0, 0, "children go first")
        XCTAssertEqual(plan.totalFootprintBytes, r.ghostBytes)
    }

    // MARK: - The backend

    private func backend(_ s: DemoScenario) -> Backend { DemoBackend.make(s, seconds: 0, now: { Fx.now }) }

    private func plan(_ b: Backend, batch: String = "t") async -> (ScanResult, StopPlan) {
        let raw = await b.scan()
        let r = Scan.analyze(raw, prefs: prefs, now: raw.scannedAt)
        return (r, StopPlanner.plan(.ghosts(groupIDs: r.groups.filter { $0.ghostCount > 0 }.map(\.id)), in: r,
                                    world: Scan.world(raw), prefs: prefs, now: raw.scannedAt, batchID: batch))
    }

    func testIsDemoAndTheLogStartsWithHistory() {
        XCTAssertTrue(backend(.leftovers).isDemo)
        XCTAssertFalse(backend(.leftovers).loadLog().isEmpty)
        XCTAssertTrue(backend(.quiet).loadLog().isEmpty)
    }

    func testStopRemovesTheGhostsAndLogsEveryTarget() async {
        let b = backend(.leftovers)
        let (_, plan) = await plan(b)
        let before = b.loadLog().count
        let seen = Counter()
        let outcome = await b.stop(plan, prefs) { _ in seen.bump() }
        XCTAssertEqual(outcome.stoppedCount, 183)
        XCTAssertEqual(seen.value, 183)
        XCTAssertEqual(Format.bytes(outcome.heldBytes), "9.4 GB")
        XCTAssertTrue(outcome.survivors.isEmpty)
        let raw = await b.scan()
        let after = Scan.analyze(raw, prefs: prefs, now: raw.scannedAt)
        XCTAssertEqual(after.ghostCount, 0)
        XCTAssertEqual(after.maybeCount, 4, "Maybes are never in a bulk stop")
        let log = b.loadLog()
        XCTAssertEqual(log.count, before + 183)
        XCTAssertTrue(log.suffix(183).allSatisfy { $0.batchID == "t" && $0.result == .stopped })
        XCTAssertFalse(log.contains { ActivityLog.encode($0).contains("/Users/") }, "no paths in the log")
    }

    func testTheSamePlanTwiceFindsEverythingGone() async {
        let b = backend(.leftovers)
        let (_, plan) = await plan(b)
        _ = await b.stop(plan, prefs) { _ in }
        let again = await b.stop(plan, prefs) { _ in }
        XCTAssertEqual(again.results.count, 183)
        XCTAssertTrue(again.results.allSatisfy { $0.status == .alreadyGone })
        XCTAssertEqual(again.heldBytes, 0)
    }

    func testRefusedAnswersEPERMForTheCodexGroup() async {
        let b = backend(.refused)
        let (_, plan) = await plan(b)
        let outcome = await b.stop(plan, prefs) { _ in }
        let refused = outcome.results.filter { $0.status == .refused }
        XCTAssertEqual(refused.count, 40)
        XCTAssertTrue(refused.allSatisfy { $0.errno == 1 && $0.target.agent == .codex && $0.target.projectName == "bar" })
        XCTAssertEqual(outcome.stoppedCount, 143)
        let raw = await b.scan()
        XCTAssertEqual(Scan.analyze(raw, prefs: prefs, now: raw.scannedAt).ghostCount, 40, "refused processes keep running")
    }

    func testSurvivorsNeedAForceStopWhichFinishesThem() async {
        let b = backend(.survivors)
        let (_, plan) = await plan(b)
        let polite = await b.stop(plan, prefs) { _ in }
        let alive = polite.survivors
        XCTAssertFalse(alive.isEmpty)
        XCTAssertTrue(alive.contains { $0.agent == .automationBrowser })
        XCTAssertEqual(polite.stoppedCount + alive.count, 183)
        let raw = await b.scan()
        let mid = Scan.analyze(raw, prefs: prefs, now: raw.scannedAt)
        XCTAssertEqual(mid.ghostCount, alive.count, "survivors are orphans again and still Ghosts")
        let force = StopPlanner.forcePlan(from: polite, batchID: "f")
        XCTAssertEqual(force.mode, .force)
        let done = await b.stop(force, prefs) { _ in }
        XCTAssertEqual(done.results.map(\.status), Array(repeating: .forceStopped, count: alive.count))
        let end = await b.scan()
        XCTAssertEqual(Scan.analyze(end, prefs: prefs, now: end.scannedAt).ghostCount, 0)
        XCTAssertTrue(b.loadLog().contains { $0.mode == .force && $0.result == .forceStopped })
    }

    func testAStaleTargetIsLeftAlone() async {
        let b = backend(.leftovers)
        let (_, plan) = await plan(b)
        var forged = plan
        forged.targets[0].identity.startSeconds += 1   // a pid that now belongs to another incarnation
        let outcome = await b.stop(StopPlan(batchID: "x", mode: .terminate, groupIDs: [], targets: [forged.targets[0]]), prefs) { _ in }
        XCTAssertEqual(outcome.results.first?.status, .changedSinceScan)
        XCTAssertEqual(outcome.stoppedCount, 0)
    }

    func testScenarioNamesParseAsLaunchArguments() {
        for s in DemoScenario.allCases { XCTAssertEqual(DemoScenario(rawValue: s.rawValue), s) }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
