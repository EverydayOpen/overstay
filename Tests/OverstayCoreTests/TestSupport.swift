import Foundation
import XCTest
@testable import OverstayCore

/// Builders shared by the Core test suites (core owner). Everything is deterministic: `now` is fixed and ages are
/// expressed relative to it.
enum Fx {
    static let uid: UInt32 = 501
    static let home = "/Users/jane"
    static let nowSeconds: Int64 = 1_800_172_800
    static let now = Date(timeIntervalSince1970: Double(nowSeconds))
    static let selfPid: Int32 = 900

    static func proc(_ pid: Int32, ppid: Int32 = 1, path: String = "/usr/local/bin/node", name: String? = nil,
                     argv: [String] = [], cwd: String? = "/Users/jane/dev/foo", root: String? = "/Users/jane/dev/foo",
                     age: Int = 200_000, uid: UInt32 = Fx.uid, tty: UInt32? = nil, sid: Int32? = nil, leader: Bool = false,
                     stdin: StdinState = .unknown, mb: UInt64 = 50, env: [String] = []) -> ProcessSnapshot {
        ProcessSnapshot(pid: pid, ppid: ppid, pgid: pid, sid: sid, uid: uid, startSeconds: nowSeconds - Int64(age),
                        path: path, name: name, argv: argv, cwd: cwd, projectRoot: root, footprintBytes: mb << 20,
                        ttyDevice: tty, isSessionLeader: leader, stdin: stdin, envMarkers: env)
    }

    /// An orphaned MCP server (node running `mcp-server-<tag>`), a Ghost by default.
    static func mcp(_ pid: Int32, tag: String = "x", ppid: Int32 = 1, age: Int = 200_000, cwd: String? = "/Users/jane/dev/foo",
                    root: String? = "/Users/jane/dev/foo", mb: UInt64 = 50, stdin: StdinState = .unknown,
                    env: [String] = []) -> ProcessSnapshot {
        proc(pid, ppid: ppid, argv: ["node", "/Users/jane/.npm/_npx/ab/node_modules/.bin/mcp-server-\(tag)"], cwd: cwd,
             root: root, age: age, stdin: stdin, mb: mb, env: env)
    }

    /// A live Claude Code session in the default project.
    static func claude(_ pid: Int32 = 400, cwd: String? = "/Users/jane/dev/foo", root: String? = "/Users/jane/dev/foo",
                       ppid: Int32 = 310) -> ProcessSnapshot {
        proc(pid, ppid: ppid, path: "/Users/jane/.local/share/claude/versions/2.1.0", name: "claude", argv: ["claude"],
             cwd: cwd, root: root, age: 7200, mb: 400)
    }

    /// Terminal (800) > login shell (850, session leader) > Overstay (900). Use it as the base of any table.
    static func base() -> [ProcessSnapshot] {
        [proc(1, ppid: 0, path: "/sbin/launchd", name: "launchd", argv: [], cwd: nil, root: nil, uid: 0),
         proc(800, path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", argv: ["Terminal"], cwd: "/", root: nil),
         proc(850, ppid: 800, path: "/bin/zsh", argv: ["-zsh"], cwd: "/Users/jane", root: nil, tty: 1, sid: 850, leader: true),
         proc(selfPid, ppid: 850, path: "/Applications/Overstay.app/Contents/MacOS/Overstay", argv: ["Overstay"], cwd: "/", root: nil, age: 60, tty: 1, sid: 850)]
    }

    static func raw(_ extra: [ProcessSnapshot], withBase: Bool = true) -> RawScan {
        RawScan(processes: (withBase ? base() : []) + extra, selfPid: selfPid, uid: uid, home: home, scannedAt: now)
    }

    static func world(_ extra: [ProcessSnapshot]) -> World { World(raw(extra)) }

    static func classify(_ p: ProcessSnapshot, with extra: [ProcessSnapshot] = [], prefs: Preferences = .default) -> ClassifiedProcess {
        Classifier.classify(p, in: world([p] + extra), prefs: prefs, now: now)
    }

    static func tier(_ p: ProcessSnapshot, with extra: [ProcessSnapshot] = [], prefs: Preferences = .default) -> Classification {
        classify(p, with: extra, prefs: prefs).tier
    }

    /// Reads `Fixtures/<name>.json` next to this file (not bundled, so Linux builds stay warning-free).
    static func fixture(_ name: String) throws -> Data {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try Data(contentsOf: dir.appendingPathComponent(name + ".json"))
    }
}

/// The compact JSON form of a process used by the fixture tables.
struct FixtureProc: Decodable {
    var pid: Int32
    var ppid: Int32
    var uid: UInt32?
    var path: String
    var name: String?
    var argv: [String]?
    var cwd: String?
    var root: String?
    var age: Int?
    var tty: UInt32?
    var sid: Int32?
    var leader: Bool?
    var stdin: StdinState?
    var mb: UInt64?
    var env: [String]?
}

struct FixtureTable: Decodable {
    var name: String
    var selfPid: Int32
    var uid: UInt32
    var home: String
    var now: Int64
    var processes: [FixtureProc]
    var expect: [String: String]
    var absent: [Int32]?

    static func load(_ file: String) throws -> FixtureTable {
        try JSONDecoder().decode(FixtureTable.self, from: Fx.fixture(file))
    }

    var nowDate: Date { Date(timeIntervalSince1970: Double(now)) }

    var raw: RawScan {
        RawScan(processes: processes.map {
            ProcessSnapshot(pid: $0.pid, ppid: $0.ppid, pgid: $0.pid, sid: $0.sid, uid: $0.uid ?? uid,
                            startSeconds: now - Int64($0.age ?? 200_000), path: $0.path, name: $0.name, argv: $0.argv ?? [],
                            cwd: $0.cwd, projectRoot: $0.root, footprintBytes: ($0.mb ?? 0) << 20, ttyDevice: $0.tty,
                            isSessionLeader: $0.leader ?? false, stdin: $0.stdin ?? .unknown, envMarkers: $0.env ?? [])
        }, selfPid: selfPid, uid: uid, home: home, scannedAt: nowDate)
    }
}
