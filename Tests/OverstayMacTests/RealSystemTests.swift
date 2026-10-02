import XCTest
import Darwin
import OverstayCore
@testable import OverstayMac

/// Thread-safe sink for the `progress` and `log` callbacks.
private final class Sink<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func add(_ o: T) { lock.lock(); items.append(o); lock.unlock() }
    var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
}

private struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

/// BUILD_PLAN §6.3: real processes, real scans, real signals. The fixture is started by the test (tests may use
/// `Foundation.Process`; the product may not), orphaned to launchd, found by the product's own scanner, classified
/// by Core and stopped by `Signaller`. Everything is VERIFY until CI has run it on macOS.
final class RealSystemTests: XCTestCase {
    private var cleanup: [ProcessIdentity] = []

    override func tearDown() {
        // Only a process that is still exactly the fixture we started is ever force-ended here.
        for id in cleanup {
            if let s = ProcessScanner.snapshot(pid: id.pid), s.identity == id { Darwin.kill(id.pid, SIGKILL) }
        }
        cleanup = []
        super.tearDown()
    }

    // MARK: helpers

    /// +1 hour: the age gate has a 1 minute floor, so tests move the clock instead of the setting.
    private let later: @Sendable () -> Date = { Date().addingTimeInterval(3600) }

    private func realPath(_ path: String) throws -> String {
        guard let r = realpath(path, nil) else { throw TestError("realpath failed for \(path)") }
        defer { free(r) }
        return String(cString: r)
    }

    private func fixtureURL() throws -> URL {
        let url = Bundle(for: RealSystemTests.self).bundleURL.deletingLastPathComponent().appendingPathComponent("OverstayFixture")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw TestError("OverstayFixture not built next to the test bundle (\(url.path)). Does `swift test` build executable targets?")
        }
        return url
    }

    /// A temp folder that looks like a project (`.git` inside). Letters only, so Scrub cannot mistake it for a secret.
    private func makeProject() throws -> URL {
        let letters = String((0..<12).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("overstay-proj-\(letters)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return URL(fileURLWithPath: try realPath(dir.path), isDirectory: true)
    }

    /// By resolved path, not name: the process name of an exec through a symlink is not guaranteed (VERIFY).
    private func find(cwd: String, in raw: RawScan) -> ProcessSnapshot? {
        raw.processes.first { $0.path.hasSuffix("/OverstayFixture") && $0.cwd == cwd }
    }

    /// `<dir>/node_modules/.bin/mcp-server-fixture`, a symlink to the fixture. Signatures judge a non-launcher by its own
    /// argv[0], so the MCP-style name has to be the name the program is started under, not an argument.
    private func fixtureLink(in dir: URL) throws -> URL {
        let bin = dir.appendingPathComponent("node_modules/.bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let link = bin.appendingPathComponent("mcp-server-fixture")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: try fixtureURL())
        return link
    }

    /// Starts the fixture detached: `sh -c '"$0" &' <link>` returns at once, so the fixture's parent is gone and launchd
    /// adopts it. With `ignoreTerm`, `trap '' TERM` runs first; ignored signals are inherited across exec.
    private func spawnOrphan(ignoreTerm: Bool = false) throws -> (identity: ProcessIdentity, dir: URL) {
        let dir = try makeProject()
        let link = try fixtureLink(in: dir)
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.currentDirectoryURL = dir
        sh.arguments = ["-c", (ignoreTerm ? "trap '' TERM; " : "") + "\"$0\" </dev/null >/dev/null 2>&1 &", link.path]
        try sh.run()
        sh.waitUntilExit()

        var found: ProcessSnapshot?
        for _ in 0..<100 {
            found = find(cwd: dir.path, in: ProcessScanner.scan())
            if let f = found, f.ppid == 1 { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard let f = found else { throw TestError("the fixture never showed up in a scan (cwd \(dir.path))") }
        cleanup.append(f.identity)
        guard f.ppid == 1 else {
            throw XCTSkip("the orphan was not adopted by launchd on this machine (ppid \(f.ppid)); BUILD_PLAN risk R11")
        }
        return (f.identity, dir)
    }

    private func isGone(_ id: ProcessIdentity) -> Bool {
        ProcessScanner.snapshot(pid: id.pid).map { $0.identity != id } ?? true
    }

    /// Scan -> classify -> plan, with the clock moved forward. Fails with the classifier's own words when an orphan is not a Ghost.
    private func ghostPlan(for ids: [ProcessIdentity], batch: String) throws -> StopPlan {
        let raw = ProcessScanner.scan()
        let at = later()
        let world = Scan.world(raw)
        let all = Classifier.classifyAll(world, prefs: Preferences(), now: at)
        for id in ids {
            guard let c = all.first(where: { $0.process.pid == id.pid }) else { throw TestError("fixture missing from classification") }
            guard c.tier == .ghost else {
                throw TestError("expected ghost, got \(c.tier): \(c.why) | argv: \(c.process.argv) | tty: \(String(describing: c.process.ttyDevice))")
            }
        }
        let result = Scan.analyze(raw, prefs: Preferences(), now: at)
        let groups = result.groups.filter { g in g.processes.contains { c in ids.contains { $0.pid == c.process.pid } } }
        XCTAssertFalse(groups.isEmpty, "ghosts are in no group")
        let plan = StopPlanner.plan(.ghosts(groupIDs: groups.map(\.id)), in: result, world: world, prefs: Preferences(), now: at, batchID: batch)
        XCTAssertEqual(Set(plan.targets.map(\.identity.pid)), Set(ids.map(\.pid)), "only the fixtures are selected: \(plan.skipped)")
        return plan
    }

    private func ghostPlan(for id: ProcessIdentity, batch: String) throws -> StopPlan { try ghostPlan(for: [id], batch: batch) }

    private func runPlan(_ plan: StopPlan, _ sink: Sink<TargetOutcome> = Sink()) async -> StopOutcome {
        await Signaller.run(plan, prefs: Preferences(), now: later, progress: { sink.add($0) }, log: { _ in true })
    }

    // MARK: the scanner

    func testOwnProcessSnapshot() throws {
        let s = try XCTUnwrap(ProcessScanner.snapshot(pid: getpid()))
        XCTAssertEqual(s.pid, getpid())
        XCTAssertEqual(s.ppid, getppid())
        XCTAssertEqual(s.uid, getuid())
        XCTAssertEqual(s.sid, getsid(0))
        XCTAssertFalse(s.path.isEmpty)
        XCTAssertFalse(s.argv.isEmpty)
        XCTAssertNotNil(s.cwd)
        XCTAssertGreaterThan(s.footprintBytes, 1_000_000)
        XCTAssertGreaterThan(s.startSeconds, 1_600_000_000)
        XCTAssertLessThan(s.age(at: Date()), 3600 * 24)
    }

    func testScanSeesSelfAndLaunchdWithoutZombiesOrDuplicates() {
        let raw = ProcessScanner.scan()
        XCTAssertEqual(raw.selfPid, getpid())
        XCTAssertEqual(raw.uid, getuid())
        XCTAssertEqual(Set(raw.processes.map(\.pid)).count, raw.processes.count)
        XCTAssertNotNil(raw.processes.first { $0.pid == getpid() })
        let launchd = raw.processes.first { $0.pid == 1 }
        XCTAssertEqual(launchd?.uid, 0)
        XCTAssertEqual(launchd?.argv, [], "other users' processes carry no argv")
        XCTAssertNil(launchd?.cwd)
        XCTAssertEqual(launchd?.footprintBytes, 0)
        XCTAssertTrue(raw.processes.filter { $0.uid != getuid() }.allSatisfy { $0.argv.isEmpty && $0.cwd == nil })
    }

    func testSnapshotOfNothingIsNil() {
        XCTAssertNil(ProcessScanner.snapshot(pid: 0))
        XCTAssertNil(ProcessScanner.snapshot(pid: -1))
        XCTAssertNil(ProcessScanner.snapshot(pid: 2_000_000_000))
    }

    func testEnvironmentMarkersAreNamesOnly() throws {
        let key = try XCTUnwrap(EnvMarkers.allowed.first)
        let child = Process()
        child.executableURL = try fixtureURL()
        child.environment = [key: "hunter2-secret-value", "OTHER_SECRET": "hunter3-secret-value", "PATH": "/usr/bin"]
        try child.run()
        addTeardownBlock { if child.isRunning { child.terminate() } }
        var snap: ProcessSnapshot?
        for _ in 0..<100 {
            snap = ProcessScanner.snapshot(pid: child.processIdentifier)
            if snap != nil { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let s = try XCTUnwrap(snap)
        cleanup.append(s.identity)
        XCTAssertEqual(s.envMarkers, [key], "VERIFY: the marker name is seen through KERN_PROCARGS2")
        XCTAssertFalse(String(describing: s).contains("hunter"), "no environment value anywhere in the model")
        XCTAssertFalse(String(describing: ProcessScanner.scan()).contains("hunter"))
    }

    // MARK: 1. orphan -> ghost -> stop

    func testOrphanBecomesGhostAndIsStopped() async throws {
        let (id, _) = try spawnOrphan()
        let plan = try ghostPlan(for: id, batch: "t-stop")
        let seen = Sink<TargetOutcome>()
        let outcome = await runPlan(plan, seen)
        XCTAssertEqual(outcome.results.map(\.status), [.stopped], "\(outcome.results)")
        XCTAssertEqual(seen.all.map(\.status), [.stopped], "progress is reported as each target finishes")
        XCTAssertTrue(isGone(id))
        XCTAssertEqual(outcome.stoppedCount, 1)
        XCTAssertGreaterThan(outcome.heldBytes, 0)
    }

    func testStopWritesOneLogLinePerTargetAndSkipped() async throws {
        let (id, _) = try spawnOrphan()
        var plan = try ghostPlan(for: id, batch: "t-log")
        plan.skipped = [SkippedTarget(pid: 4242, name: "postgres", reason: "Protected: database server.")]
        let lines = Sink<ActivityEntry>()
        let outcome = await Signaller.run(plan, prefs: Preferences(), now: later, progress: { _ in },
                                          log: { lines.add($0); return true })
        XCTAssertEqual(outcome.stoppedCount, 1)
        XCTAssertEqual(Set(lines.all.map(\.pid)), [id.pid, 4242])
        XCTAssertEqual(lines.all.first { $0.pid == 4242 }?.result, .blocked)
        XCTAssertEqual(lines.all.filter { $0.pid == id.pid }.map(\.result), [.signalled, .stopped], "write-ahead line, then the outcome")
        XCTAssertEqual(Set(lines.all.map(\.batchID)), ["t-log"])
        XCTAssertTrue(isGone(id))
    }

    /// Fail closed (BUILD_PLAN §3 rule 14): if the log cannot be written, nothing is signalled.
    func testUnwritableLogMeansNothingIsSignalled() async throws {
        let (id, _) = try spawnOrphan()
        var plan = try ghostPlan(for: id, batch: "t-nolog")
        plan.skipped = [SkippedTarget(pid: 4242, name: "postgres", reason: "Protected.")]
        let outcome = await Signaller.run(plan, prefs: Preferences(), now: later, progress: { _ in }, log: { _ in false })
        XCTAssertEqual(outcome.results.map(\.status), [.blocked])
        XCTAssertEqual(outcome.results.first?.detail, "Activity log is not writable")
        XCTAssertFalse(isGone(id))
    }

    /// Deepest wave first: the target with the larger `depth` is signalled, and has exited, before the next wave starts.
    func testDeepestWaveGoesFirst() async throws {
        let (a, _) = try spawnOrphan()
        let (b, _) = try spawnOrphan()
        var plan = try ghostPlan(for: [a, b], batch: "t-waves")
        XCTAssertEqual(plan.targets.count, 2)
        plan.targets[0].depth = 0
        plan.targets[1].depth = 1
        let deeper = plan.targets[1].identity.pid
        let outcome = await runPlan(plan)
        XCTAssertEqual(outcome.results.map(\.status), [.stopped, .stopped])
        XCTAssertEqual(outcome.results.first?.target.identity.pid, deeper)
        XCTAssertTrue(isGone(a) && isGone(b))
    }

    func testLiveBackendScanWorks() async throws {
        let raw = await LiveBackend.make().scan()
        XCTAssertEqual(raw.selfPid, getpid())
    }

    // MARK: 2. protected, ancestors, pid 1, live parent

    func testLiveParentMakesItIgnoredAndOurAncestryIsNeverSelectable() async throws {
        let dir = try makeProject()
        let child = Process()
        child.executableURL = try fixtureLink(in: dir)
        child.currentDirectoryURL = dir
        try child.run()
        addTeardownBlock { if child.isRunning { child.terminate() } }
        var fixture: ProcessSnapshot?
        for _ in 0..<100 {
            fixture = ProcessScanner.snapshot(pid: child.processIdentifier)
            if fixture != nil { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let snapshot = try XCTUnwrap(fixture)
        cleanup.append(snapshot.identity)
        // Not vacuous: without a signature match the process would be .ignored for the wrong reason.
        XCTAssertNotNil(Signatures.match(snapshot), "the fixture must look like an MCP server: \(snapshot.argv) \(snapshot.path)")

        let raw = ProcessScanner.scan()
        let at = later()
        let world = Scan.world(raw)
        let all = Classifier.classifyAll(world, prefs: Preferences(), now: at)
        XCTAssertEqual(all.first { $0.process.pid == child.processIdentifier }?.tier, .ignored, "a live parent means not a leftover")
        let ancestry = Set(world.ancestors).union([getpid(), 1])
        for c in all where ancestry.contains(c.process.pid) {
            XCTAssertFalse(c.tier.isListed, "\(c.process.name) is ours or an ancestor and must never be listed")
        }
        let result = Scan.analyze(raw, prefs: Preferences(), now: at)
        let bulk = StopPlanner.plan(.ghosts(groupIDs: result.groups.map(\.id)), in: result, world: world, prefs: Preferences(), now: at, batchID: "t-all")
        XCTAssertTrue(Set(bulk.targets.map(\.identity.pid)).isDisjoint(with: ancestry))
    }

    func testHandBuiltPlanAgainstPid1SelfAndAncestorsSendsNothing() async throws {
        let raw = ProcessScanner.scan()
        var pids: [Int32] = [1, getpid(), getppid()]
        var p = getppid()
        while p > 1, pids.count < 70, let up = ProcessScanner.ppid(of: p) { pids.append(up); p = up }
        pids = Array(Set(pids)).sorted()
        let targets: [StopTarget] = pids.map { pid in
            let id = raw.processes.first { $0.pid == pid }?.identity
                ?? ProcessIdentity(pid: pid, startSeconds: 0, startMicroseconds: 0, uid: getuid(), path: "")
            return StopTarget(identity: id, name: "x", signatureID: "mcp-server-named", agent: .unattributed, projectName: nil,
                              approvedTier: .ghost, footprintBytes: 0, depth: 0, why: "hand-built")
        }
        for mode in [StopMode.terminate, .force] {
            let plan = StopPlan(batchID: "t-blocked-\(mode.rawValue)", mode: mode, groupIDs: [], targets: targets, graceSeconds: 0.3)
            let outcome = await runPlan(plan)
            XCTAssertEqual(outcome.results.count, targets.count)
            XCTAssertTrue(outcome.results.allSatisfy { $0.status == .blocked }, "\(outcome.results.map { "\($0.target.identity.pid): \($0.status)" })")
        }
        XCTAssertNotNil(ProcessScanner.snapshot(pid: getppid()), "our parent is untouched")
        XCTAssertNotNil(ProcessScanner.snapshot(pid: 1))
    }

    func testPidZeroAndNegativePidsAreBlockedAndNothingIsSent() async {
        let ids = [0, -1, -getpid(), 1].map { ProcessIdentity(pid: $0, startSeconds: 1, startMicroseconds: 0, uid: getuid(), path: "/x") }
        let targets = ids.map {
            StopTarget(identity: $0, name: "x", signatureID: "mcp-server-named", agent: .unattributed, projectName: nil,
                       approvedTier: .ghost, footprintBytes: 0, depth: 0, why: "hand-built")
        }
        let outcome = await runPlan(StopPlan(batchID: "t-neg", mode: .force, groupIDs: [], targets: targets, graceSeconds: 0.2))
        XCTAssertTrue(outcome.results.allSatisfy { $0.status == .blocked }, "\(outcome.results.map(\.status))")
    }

    // MARK: 3. pid reuse

    func testChangedStartTimeIsNotSignalled() async throws {
        let (id, _) = try spawnOrphan()
        var plan = try ghostPlan(for: id, batch: "t-reuse")
        plan.targets[0].identity.startSeconds += 1
        let outcome = await runPlan(plan)
        XCTAssertEqual(outcome.results.map(\.status), [.changedSinceScan])
        XCTAssertFalse(isGone(id), "the process was left alone")
    }

    func testChangedPathOrUidIsNotSignalled() async throws {
        let (id, _) = try spawnOrphan()
        let plan = try ghostPlan(for: id, batch: "t-reuse2")
        var otherPath = plan, otherUid = plan, otherMicros = plan
        otherPath.targets[0].identity.path += "x"
        otherUid.targets[0].identity.uid += 1
        otherMicros.targets[0].identity.startMicroseconds += 1
        for p in [otherPath, otherUid, otherMicros] {
            let outcome = await runPlan(p)
            XCTAssertTrue([.changedSinceScan, .blocked].contains(outcome.results[0].status), "\(outcome.results[0].status)")
            XCTAssertFalse(isGone(id))
        }
    }

    func testAlreadyGoneIsReportedAsSuch() async throws {
        let (id, _) = try spawnOrphan()
        let plan = try ghostPlan(for: id, batch: "t-gone")
        Darwin.kill(id.pid, SIGKILL)   // the test ends it itself, behind the product's back
        for _ in 0..<50 where !isGone(id) { Thread.sleep(forTimeInterval: 0.1) }
        let outcome = await runPlan(plan)
        XCTAssertEqual(outcome.results.map(\.status), [.alreadyGone])
        XCTAssertEqual(outcome.stoppedCount, 0)
        XCTAssertEqual(outcome.heldBytes, 0)
    }

    // MARK: 4. survivors and force

    func testSigtermProofProcessSurvivesThenForceStopsOnlyViaForcePlan() async throws {
        let (id, _) = try spawnOrphan(ignoreTerm: true)
        var plan = try ghostPlan(for: id, batch: "t-surv")
        plan.graceSeconds = 1
        let first = await runPlan(plan)
        XCTAssertEqual(first.results.map(\.status), [.survived], "\(first.results)")
        XCTAssertFalse(isGone(id), "a polite plan never escalates by itself")
        XCTAssertEqual(first.survivors.map(\.identity.pid), [id.pid])

        let force = StopPlanner.forcePlan(from: first, batchID: "t-force")
        XCTAssertEqual(force.mode, .force)
        let second = await runPlan(force)
        XCTAssertEqual(second.results.map(\.status), [.forceStopped], "\(second.results)")
        XCTAssertTrue(isGone(id))
    }

    // MARK: 5. diagnostics artifact for CI

    func testWriteDiagnosticsArtifactWhenAsked() throws {
        guard let out = ProcessInfo.processInfo.environment["OVERSTAY_DIAG_OUT"], !out.isEmpty else {
            throw XCTSkip("OVERSTAY_DIAG_OUT is not set")
        }
        let raw = ProcessScanner.scan()
        let text = Diagnostics.text(raw: raw, prefs: Preferences(), now: Date(),
                                    osVersion: ProcessInfo.processInfo.operatingSystemVersionString)
        XCTAssertFalse(text.isEmpty)
        XCTAssertFalse(text.contains(raw.home + "/"), "no full home path")
        try text.write(toFile: out, atomically: true, encoding: .utf8)
    }
}
