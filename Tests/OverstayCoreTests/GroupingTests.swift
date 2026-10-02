import Foundation
import XCTest
@testable import OverstayCore

final class GroupingTests: XCTestCase {
    private func analyze(_ extra: [ProcessSnapshot], prefs: Preferences = .default) -> ScanResult {
        Scan.analyze(Fx.raw(extra), prefs: prefs, now: Fx.now)
    }

    func testProjectNamer() {
        let home = "/Users/jane"
        XCTAssertEqual(ProjectNamer.project(projectRoot: "/Users/jane/dev/foo", cwd: "/Users/jane/dev/foo/src", home: home),
                       Project(name: "foo", root: "/Users/jane/dev/foo"))
        XCTAssertEqual(ProjectNamer.project(projectRoot: nil, cwd: "/Users/jane/scratch/", home: home)?.name, "scratch")
        XCTAssertNil(ProjectNamer.project(projectRoot: nil, cwd: "/", home: home))
        XCTAssertNil(ProjectNamer.project(projectRoot: nil, cwd: "/Users/jane", home: home))
        XCTAssertNil(ProjectNamer.project(projectRoot: nil, cwd: "/Users/jane/", home: "/Users/jane/"))
        XCTAssertNil(ProjectNamer.project(projectRoot: nil, cwd: nil, home: home))
        XCTAssertNil(ProjectNamer.project(projectRoot: "", cwd: "", home: home))
        XCTAssertEqual(ProjectNamer.project(projectRoot: "/", cwd: "/tmp/x", home: home)?.name, "x", "a useless root falls through to cwd")
    }

    func testGroupsByAgentAndProjectWithGhostWeightFirst() {
        let r = analyze([Fx.mcp(500, tag: "a", mb: 100), Fx.mcp(501, tag: "b", mb: 100),
                         Fx.mcp(510, tag: "c", cwd: "/Users/jane/dev/bar", root: "/Users/jane/dev/bar", mb: 500),
                         Fx.mcp(520, tag: "d", mb: 40, env: ["CLAUDECODE"])])
        XCTAssertEqual(r.groups.map(\.id), ["unattributed|/Users/jane/dev/bar", "unattributed|/Users/jane/dev/foo", "claudeCode|/Users/jane/dev/foo"])
        XCTAssertEqual(r.groups.map(\.ghostCount), [1, 2, 1])
        XCTAssertEqual(r.groups[0].project?.name, "bar")
        XCTAssertEqual(r.ghostCount, 4)
        XCTAssertEqual(r.ghostBytes, 740 << 20)
        XCTAssertEqual(Grouping.title(r.groups[0]), "Agent tool servers")
        XCTAssertEqual(Grouping.title(r.groups[2]), "Claude Code")
        XCTAssertFalse(r.isQuiet)
    }

    func testGroupSortTiesBreakDeterministically() {
        let a = Fx.mcp(500, cwd: "/Users/jane/dev/aaa", root: "/Users/jane/dev/aaa", mb: 10)
        let b = Fx.mcp(501, cwd: "/Users/jane/dev/bbb", root: "/Users/jane/dev/bbb", mb: 10)
        let one = analyze([a, b]).groups.map(\.id)
        let two = analyze([b, a]).groups.map(\.id)
        XCTAssertEqual(one, two)
    }

    func testMaybesDoNotWeighAndGroupsWithOnlyMaybesStillShow() {
        let r = analyze([Fx.mcp(500, mb: 100), Fx.mcp(501, tag: "y", age: 30, mb: 900)])
        XCTAssertEqual(r.groups.count, 1)
        XCTAssertEqual(r.groups[0].ghostCount, 1)
        XCTAssertEqual(r.groups[0].maybeCount, 1)
        XCTAssertEqual(r.groups[0].ghostBytes, 100 << 20)
        XCTAssertEqual(r.groups[0].totalBytes, 1000 << 20)
        let only = analyze([Fx.mcp(502, age: 30)])
        XCTAssertEqual(only.ghostCount, 0)
        XCTAssertEqual(only.maybeCount, 1)
        XCTAssertFalse(only.isQuiet)
    }

    func testMembersAreParentsBeforeChildren() {
        let wrapper = Fx.proc(900_001, path: "/bin/sh", argv: ["sh", "-c", "mcp-server-time /Users/jane/dev/foo"], mb: 2)
        let leaf = Fx.mcp(100, tag: "time", ppid: 900_001)
        let leaf2 = Fx.mcp(50, tag: "time", ppid: 900_001)
        let r = analyze([leaf, leaf2, wrapper])
        XCTAssertEqual(r.groups.count, 1)
        XCTAssertEqual(r.groups[0].processes.map(\.process.pid), [900_001, 50, 100])
    }

    func testQuietWhenNothingMatches() {
        let r = analyze([Fx.proc(500, argv: ["node", "server.js"]), Fx.claude(400)])
        XCTAssertTrue(r.isQuiet)
        XCTAssertGreaterThan(r.examinedCount, 0)
        XCTAssertEqual(r.home, Fx.home)
    }

    func testProcessesWithoutAProjectGroupByAgentAlone() {
        let a = Fx.proc(500, path: "/Users/jane/Library/Caches/ms-playwright/chromium-1/Chromium.app/Contents/MacOS/Chromium",
                        argv: ["Chromium", "--headless", "--remote-debugging-pipe"], cwd: "/", root: nil)
        let r = analyze([a])
        XCTAssertEqual(r.groups.map(\.id), ["automationBrowser|-"])
        XCTAssertNil(r.groups[0].project)
    }
}

final class FixtureTableTests: XCTestCase {
    func testMixedTableClassifiesEveryProcessAsExpected() throws {
        let table = try FixtureTable.load("table_mixed")
        let world = Scan.world(table.raw)
        let all = Classifier.classifyAll(world, prefs: .default, now: table.nowDate)
        let byPid = Dictionary(uniqueKeysWithValues: all.map { ($0.process.pid, $0) })
        for (key, want) in table.expect {
            let pid = Int32(key)!
            guard let got = byPid[pid] else { return XCTFail("pid \(pid) was not classified") }
            XCTAssertEqual(got.tier.rawValue, want, "pid \(pid): \(got.why)")
        }
        for pid in table.absent ?? [] { XCTAssertNil(byPid[pid], "pid \(pid) belongs to another user") }
        XCTAssertEqual(Set(byPid.keys).subtracting((table.absent ?? [])).count, table.expect.count, "every same-user pid has an expectation")
    }

    func testMixedTableGroupsAndPlans() throws {
        let table = try FixtureTable.load("table_mixed")
        let result = Scan.analyze(table.raw, prefs: .default, now: table.nowDate)
        let ghostsByGroup = Dictionary(uniqueKeysWithValues: result.groups.map { ($0.id, $0.ghosts.map(\.process.pid).sorted()) })
        XCTAssertEqual(ghostsByGroup["unattributed|/Users/jane/dev/bar"], [510, 520, 521, 640])
        XCTAssertEqual(ghostsByGroup["automationBrowser|-"], [530])
        XCTAssertEqual(ghostsByGroup["unattributed|/Users/jane/dev/foo"], [])
        XCTAssertEqual(result.ghostCount, 5)
        // Maybes: the one beside a live session, the generic dev server and the young one.
        XCTAssertEqual(result.groups.flatMap(\.maybes).map(\.process.pid).sorted(), [500, 610, 630])

        let world = Scan.world(table.raw)
        let plan = StopPlanner.plan(.ghosts(groupIDs: result.groups.map(\.id)), in: result, world: world, prefs: .default,
                                    now: table.nowDate, batchID: "b1")
        XCTAssertEqual(Set(plan.targets.map(\.identity.pid)), [510, 520, 521, 530, 640])
        XCTAssertTrue(plan.skipped.isEmpty)
        let order = plan.targets.map(\.identity.pid)
        XCTAssertLessThan(order.firstIndex(of: 521)!, order.firstIndex(of: 520)!, "the child goes before its wrapper")
        // None of the protected, ignored or live-session pids can ever be in a plan.
        for never in [200, 300, 310, 900, 400, 410, 540, 550, 560, 570, 580, 590, 600, 650, 1, 100, 620] {
            XCTAssertFalse(order.contains(Int32(never)), "pid \(never)")
        }
    }
}
