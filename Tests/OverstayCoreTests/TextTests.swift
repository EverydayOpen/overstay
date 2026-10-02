import Foundation
import XCTest
@testable import OverstayCore

final class FormatTests: XCTestCase {
    func testBytes() {
        XCTAssertEqual(Format.bytes(0), "0 KB")
        XCTAssertEqual(Format.bytes(1023), "0 KB")
        XCTAssertEqual(Format.bytes(512 << 10), "512 KB")
        XCTAssertEqual(Format.bytes(412 << 20), "412 MB")
        XCTAssertEqual(Format.bytes(1023 << 20), "1023 MB")
        XCTAssertEqual(Format.bytes((1024 << 20) - 1), "1.0 GB", "rounds up to the next unit rather than printing 1024 MB")
        XCTAssertEqual(Format.bytes(1 << 30), "1.0 GB")
        XCTAssertEqual(Format.bytes(UInt64(9.4 * 1_073_741_824)), "9.4 GB")
        XCTAssertEqual(Format.bytes(UInt64(99.94 * 1_073_741_824)), "99.9 GB")
        XCTAssertEqual(Format.bytes(100 << 30), "100 GB")
        XCTAssertEqual(Format.bytes(UInt64(150.4 * 1_073_741_824)), "150 GB")
        XCTAssertEqual(Format.bytes(2 << 40), "2.0 TB")
    }

    func testAge() {
        XCTAssertEqual(Format.age(seconds: -5), "just now")
        XCTAssertEqual(Format.age(seconds: 59), "just now")
        XCTAssertEqual(Format.age(seconds: 60), "1 min")
        XCTAssertEqual(Format.age(seconds: 720), "12 min")
        XCTAssertEqual(Format.age(seconds: 3599), "59 min")
        XCTAssertEqual(Format.age(seconds: 3600), "1 hour")
        XCTAssertEqual(Format.age(seconds: 3 * 3600 + 10), "3 hours")
        XCTAssertEqual(Format.age(seconds: 86_400), "1 day")
        XCTAssertEqual(Format.age(seconds: 3 * 86_400), "3 days")
    }

    func testStartedNeverSaysEnded() {
        XCTAssertEqual(Format.started(seconds: 3 * 86_400), "started 3 days ago")
        XCTAssertEqual(Format.started(seconds: 5), "started just now")
        for s in [0, 100, 10_000, 1_000_000] { XCTAssertFalse(Format.started(seconds: s).contains("ended")) }
    }

    func testCount() {
        XCTAssertEqual(Format.count(1, "process"), "1 process")
        XCTAssertEqual(Format.count(183, "process"), "183 processes")
        XCTAssertEqual(Format.count(0, "leftover"), "0 leftovers")
        XCTAssertEqual(Format.count(2, "leftover process"), "2 leftover processes")
        XCTAssertEqual(Format.count(2, "copy"), "2 copies")
        XCTAssertEqual(Format.count(2, "day"), "2 days")
        XCTAssertEqual(Format.count(2, "match"), "2 matches")
    }
}

final class ShareCardTests: XCTestCase {
    private func found() -> ScanResult {
        Scan.analyze(Fx.raw([Fx.mcp(500, mb: 3000), Fx.mcp(501, mb: 100),
                             Fx.mcp(510, cwd: "/Users/jane/dev/bar", root: "/Users/jane/dev/bar", mb: 2000)]
                            + [Fx.mcp(520, cwd: "/Users/jane/dev/baz", root: "/Users/jane/dev/baz", mb: 1000, env: ["CLAUDECODE"])]),
                     prefs: .default, now: Fx.now)
    }

    func testFoundCardHasNoProjectNamesByDefault() {
        let card = ShareCardText.card(found: found(), includeProjectNames: false, isSample: false)
        XCTAssertEqual(card.kind, .found)
        XCTAssertEqual(card.processCount, 4)
        XCTAssertEqual(card.bytes, 6100 << 20)
        XCTAssertEqual(card.topAgents, ["Agent tool servers", "Claude Code"])
        XCTAssertEqual(card.projectNames, [])
        XCTAssertEqual(ShareCardText.headline(card), "Your AI agents left 6.0 GB running.")
        XCTAssertEqual(ShareCardText.subline(card), "4 leftover processes · Agent tool servers, Claude Code")
        let text = ShareCardText.plainText(card, footer: "everydayopen.github.io/overstay")
        XCTAssertFalse(text.contains("foo") || text.contains("bar") || text.contains("/Users"))
        XCTAssertTrue(text.hasSuffix("everydayopen.github.io/overstay"))
    }

    func testProjectNamesAppearOnlyWhenIncluded() {
        let card = ShareCardText.card(found: found(), includeProjectNames: true, isSample: false)
        XCTAssertEqual(card.projectNames, ["foo", "bar", "baz"])
        XCTAssertEqual(ShareCardText.subline(card), "4 leftover processes · Agent tool servers, Claude Code · foo, bar, baz")
    }

    func testMaybesAreNotCounted() {
        let r = Scan.analyze(Fx.raw([Fx.mcp(500, age: 30, mb: 900), Fx.mcp(501, mb: 10)]), prefs: .default, now: Fx.now)
        let card = ShareCardText.card(found: r, includeProjectNames: false, isSample: false)
        XCTAssertEqual(card.processCount, 1)
        XCTAssertEqual(card.bytes, 10 << 20)
        let quiet = ShareCardText.card(found: Scan.analyze(Fx.raw([]), prefs: .default, now: Fx.now), includeProjectNames: true, isSample: false)
        XCTAssertEqual(ShareCardText.headline(quiet), "All quiet. Nothing left behind.")
        XCTAssertEqual(ShareCardText.subline(quiet), "0 leftover processes")
    }

    func testStoppedCardCountsOnlyWhatExited() {
        func t(_ pid: Int32, _ mb: UInt64, agent: AgentKind, project: String?) -> StopTarget {
            StopTarget(identity: Fx.mcp(pid).identity, name: "node", signatureID: "mcp-server-named", agent: agent, projectName: project,
                       approvedTier: .ghost, footprintBytes: mb << 20, depth: 0, why: "t")
        }
        let results = [TargetOutcome(target: t(1, 1000, agent: .claudeCode, project: "foo"), status: .stopped),
                       TargetOutcome(target: t(2, 3000, agent: .codex, project: "bar"), status: .forceStopped),
                       TargetOutcome(target: t(3, 9000, agent: .codex, project: "bar"), status: .survived),
                       TargetOutcome(target: t(4, 9000, agent: .cursor, project: nil), status: .changedSinceScan)]
        let outcome = StopOutcome(batchID: "b", mode: .terminate, startedAt: Fx.now, finishedAt: Fx.now.addingTimeInterval(4), results: results)
        let card = ShareCardText.card(stopped: outcome, includeProjectNames: false, isSample: true)
        XCTAssertEqual(card.kind, .stopped)
        XCTAssertEqual(card.processCount, 2)
        XCTAssertEqual(card.bytes, 4000 << 20)
        XCTAssertEqual(card.topAgents, ["Codex", "Claude Code"])
        XCTAssertTrue(card.isSample)
        XCTAssertEqual(card.date, Fx.now.addingTimeInterval(4))
        XCTAssertEqual(ShareCardText.headline(card), "Stopped 2 leftovers. 3.9 GB was held.")
        XCTAssertEqual(ShareCardText.plainText(card, footer: "").components(separatedBy: "\n").last, "Sample data")
        let one = StopOutcome(batchID: "b", mode: .terminate, startedAt: Fx.now, finishedAt: Fx.now, results: [results[0]])
        XCTAssertEqual(ShareCardText.headline(ShareCardText.card(stopped: one, includeProjectNames: true, isSample: false)),
                       "Stopped 1 leftover. 1000 MB was held.")
        let none = StopOutcome(batchID: "b", mode: .terminate, startedAt: Fx.now, finishedAt: Fx.now, results: [results[2]])
        XCTAssertEqual(ShareCardText.headline(ShareCardText.card(stopped: none, includeProjectNames: false, isSample: false)), "Nothing was stopped.")
        XCTAssertEqual(ShareCardText.card(stopped: outcome, includeProjectNames: true, isSample: false).projectNames, ["bar", "foo"])
    }

    func testTheCardNeverClaimsMoreThanItKnows() {
        let card = ShareCardText.card(found: found(), includeProjectNames: false, isSample: false)
        let text = ShareCardText.headline(card) + ShareCardText.subline(card)
        for banned in ["freed", "undo", "restore", "safe to", "killed", "ended"] { XCTAssertFalse(text.lowercased().contains(banned), banned) }
        XCTAssertEqual(ShareCardText.sampleWatermark, "Sample data")
    }
}

final class ActivityLogTests: XCTestCase {
    private func entry(pid: Int32 = 500, errno: Int32? = nil, why: String = "Parent is gone. Looks like an MCP server. No live session in foo.") -> ActivityEntry {
        ActivityEntry(timestamp: Date(timeIntervalSince1970: 1_800_000_000), batchID: "b1", mode: .terminate, pid: pid,
                      executable: "node", signatureID: "mcp-server-named", agent: .unattributed, project: "foo",
                      footprintBytes: 52_428_800, result: .refused, errno: errno, why: why)
    }

    func testRoundTrip() {
        for e in [entry(), entry(errno: 1), entry(pid: 12)] {
            XCTAssertEqual(ActivityLog.decode(line: ActivityLog.encode(e)), e)
        }
    }

    func testOneLineSortedKeysAndIsoDates() {
        let line = ActivityLog.encode(entry(errno: 1))
        XCTAssertFalse(line.contains("\n"))
        XCTAssertFalse(line.hasSuffix("\n"))
        XCTAssertTrue(line.contains("\"timestamp\":\"2027-01-15T08:00:00Z\""), line)
        let keys = ["agent", "batchID", "errno", "executable", "footprintBytes", "mode", "pid", "project", "result", "signatureID", "timestamp", "why"]
        var last = line.startIndex
        for k in keys {
            guard let r = line.range(of: "\"\(k)\":", range: last..<line.endIndex) else { return XCTFail("key \(k) missing or out of order: \(line)") }
            last = r.upperBound
        }
        XCTAssertEqual(ActivityLog.fileName, "activity.jsonl")
    }

    func testALineHoldsNoArgvEnvOrFullPaths() {
        let line = ActivityLog.encode(entry())
        XCTAssertFalse(line.contains("/Users"))
        XCTAssertFalse(line.contains("argv"))
        XCTAssertFalse(line.lowercased().contains("environment"))
        let fields = Set(Mirror(reflecting: entry()).children.compactMap(\.label))
        XCTAssertEqual(fields, ["timestamp", "batchID", "mode", "pid", "executable", "signatureID", "agent", "project", "footprintBytes", "result", "errno", "why"])
    }

    func testDecodeAllIsTolerant() {
        let a = ActivityLog.encode(entry(pid: 1)), b = ActivityLog.encode(entry(pid: 2))
        let text = "\(a)\n\n  \n{not json\n\(b)\r\n{\"pid\":3}\n"
        let (entries, skipped) = ActivityLog.decodeAll(text)
        XCTAssertEqual(entries.map(\.pid), [1, 2])
        XCTAssertEqual(skipped, 2)
        XCTAssertEqual(ActivityLog.decodeAll("").entries.count, 0)
        XCTAssertEqual(ActivityLog.decodeAll("\n\n").skippedLines, 0)
        XCTAssertNil(ActivityLog.decode(line: ""))
    }

    func testEntryFromAnOutcome() {
        let p = Fx.mcp(500)
        let t = StopTarget(identity: p.identity, name: "node", signatureID: "mcp-server-named", agent: .claudeCode, projectName: "foo",
                           approvedTier: .ghost, footprintBytes: 7, depth: 0, why: "w")
        let e = ActivityEntry(TargetOutcome(target: t, status: .refused, errno: 1), batchID: "b", mode: .terminate, at: Fx.now)
        XCTAssertEqual([e.pid, Int32(e.footprintBytes)], [500, 7])
        XCTAssertEqual(e.result, .refused)
        XCTAssertEqual(e.errno, 1)
        XCTAssertEqual(e.agent, .claudeCode)
    }
}

final class DiagnosticsTests: XCTestCase {
    func testDiagnosticsHaveCountsBlocksAndNoSecrets() throws {
        var table = try FixtureTable.load("table_mixed")
        table.processes.append(FixtureProc(pid: 700, ppid: 1, path: "/usr/local/bin/node",
                                           argv: ["node", "/Users/jane/dev/bar/node_modules/.bin/mcp-server-x", "--api-key=hunter2hunter2", "/Users/jane/dev/bar"],
                                           cwd: "/Users/jane/dev/bar", root: "/Users/jane/dev/bar", age: 90_000, mb: 10, env: ["CLAUDECODE"]))
        var raw = table.raw
        // The Mac layer scrubs before storing; do the same here.
        raw.processes = raw.processes.map { var p = $0; p.argv = Scrub.argv(p.argv); return p }
        raw.unreadableCount = 3
        let text = Diagnostics.text(raw: raw, prefs: .default, now: table.nowDate, osVersion: "15.4")
        XCTAssertTrue(text.contains("macOS: 15.4"))
        XCTAssertTrue(text.contains("Unreadable: 3"))
        XCTAssertTrue(text.contains("Examined: 23 of your processes"), text)
        XCTAssertTrue(text.contains("signature: mcp-server-named"))
        XCTAssertTrue(text.contains("signature: claude-session"), "protected matches are listed too")
        XCTAssertTrue(text.contains("env markers (names only): CLAUDECODE"))
        XCTAssertTrue(text.contains("~/dev/bar/node_modules/.bin/mcp-server-x"), "home is shown as ~")
        XCTAssertTrue(text.contains("--api-key=<redacted>"))
        XCTAssertFalse(text.contains("hunter2"))
        XCTAssertFalse(text.contains("/Users/jane"), "no full home path anywhere")
        XCTAssertFalse(text.contains("jane"))
        // Only matches get a block: Finder and the user's Chrome have none.
        XCTAssertFalse(text.contains("Finder"))
        XCTAssertFalse(text.contains("Google Chrome"))
    }

    func testQuietMachine() {
        let text = Diagnostics.text(raw: Fx.raw([]), prefs: .default, now: Fx.now, osVersion: "13.6")
        XCTAssertTrue(text.contains("Signature matches: 0"))
        XCTAssertFalse(text.contains("[1]"))
    }
}
