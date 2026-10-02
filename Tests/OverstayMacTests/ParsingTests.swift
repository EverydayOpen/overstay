import XCTest
import Darwin
import OverstayCore
@testable import OverstayMac

/// Pure-ish unit tests: the sysctl buffer parser, project-root discovery and the footprint read.
final class ParsingTests: XCTestCase {
    // MARK: ProcArgs.parse

    /// A KERN_PROCARGS2-shaped buffer: Int32 argc (little-endian), exec path, NUL padding, argv, then KEY=value entries.
    private func buffer(argc: Int32? = nil, path: String = "/opt/homebrew/bin/node", args: [String], env: [String],
                        pad: Int? = nil) -> [UInt8] {
        var b = withUnsafeBytes(of: (argc ?? Int32(args.count)).littleEndian) { Array($0) }
        // The kernel rounds path + NUL up to a multiple of 8.
        let padding = pad ?? (8 - (path.utf8.count + 1) % 8) % 8
        b += Array(path.utf8) + [0] + [UInt8](repeating: 0, count: padding)
        for a in args { b += Array(a.utf8) + [0] }
        for e in env { b += Array(e.utf8) + [0] }
        return b
    }

    func testParseArgvAndMarkers() throws {
        let key = try XCTUnwrap(EnvMarkers.allowed.first, "EnvMarkers.allowed is empty")
        let buf = buffer(args: ["node", "/x/node_modules/.bin/mcp-server-fs", "--stdio"],
                         env: ["PATH=/usr/bin", "\(key)=super-secret-value", "HOME=/Users/jane"])
        let r = try XCTUnwrap(ProcArgs.parse(buf, envKeys: EnvMarkers.allowed))
        XCTAssertEqual(r.argv, ["node", "/x/node_modules/.bin/mcp-server-fs", "--stdio"])
        XCTAssertEqual(r.envMarkers, [key])
        XCTAssertFalse(r.envMarkers.joined().contains("secret"), "only key names may leave the parser")
    }

    func testEmptyArgv0DoesNotPullInTheEnvironment() throws {
        for path in ["/bin/x", "/opt/homebrew/bin/node", "/bin/ab", "/bin/abcd"] {   // paddings 1, 1, 0 and 6
            let buf = buffer(path: path, args: ["", "--serve"], env: ["TOKEN=hunter2", "HOME=/Users/jane"])
            let r = try XCTUnwrap(ProcArgs.parse(buf, envKeys: []))
            XCTAssertEqual(r.argv, ["", "--serve"], path)
            XCTAssertFalse(r.argv.joined().contains("hunter2"), "environment values never enter argv")
        }
    }

    func testParseMatchesWholeKeysOnly() throws {
        let key = try XCTUnwrap(EnvMarkers.allowed.first)
        let buf = buffer(args: ["a"], env: ["\(key)X=1", "X\(key)=1", String(key.dropLast()) + "=1", key])   // last: no '='
        XCTAssertEqual(try XCTUnwrap(ProcArgs.parse(buf, envKeys: [key])).envMarkers, [])
    }

    func testParseWithEmptyEnvAndEmptyArgs() throws {
        XCTAssertEqual(try XCTUnwrap(ProcArgs.parse(buffer(args: [], env: []), envKeys: ["A"])).argv, [])
        XCTAssertEqual(try XCTUnwrap(ProcArgs.parse(buffer(args: ["x"], env: []), envKeys: ["A"])).envMarkers, [])
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(ProcArgs.parse([], envKeys: []))
        XCTAssertNil(ProcArgs.parse([1, 0, 0], envKeys: []))
        XCTAssertNil(ProcArgs.parse(buffer(argc: -1, args: ["a"], env: []), envKeys: []))
    }

    /// argc larger than what is there, and every possible truncation: partial results, never a crash.
    func testParseToleratesTruncation() throws {
        let full = buffer(args: ["node", "server.js", "--flag"], env: ["CLAUDECODE=1", "PATH=/usr/bin"])
        for n in 0...full.count {
            if let r = ProcArgs.parse(Array(full.prefix(n)), envKeys: ["CLAUDECODE"]) {
                XCTAssertLessThanOrEqual(r.argv.count, 3)
            }
        }
        let lying = buffer(argc: 50, args: ["node", "a"], env: [])
        XCTAssertEqual(try XCTUnwrap(ProcArgs.parse(lying, envKeys: [])).argv, ["node", "a"])
        // Cut mid-argv: the incomplete last word is still returned as far as it goes.
        let cut = Array(buffer(args: ["node", "server.js"], env: []).dropLast(4))
        XCTAssertEqual(try XCTUnwrap(ProcArgs.parse(cut, envKeys: [])).argv.first, "node")
    }

    func testParseOfOwnProcessMatchesProcessInfo() throws {
        let r = try XCTUnwrap(ProcArgs.read(pid: getpid(), envKeys: ["PATH", "HOME", "DEFINITELY_NOT_SET_XYZ"]))
        XCTAssertEqual(r.argv, CommandLine.arguments)
        XCTAssertTrue(r.envMarkers.contains("PATH"))
        XCTAssertFalse(r.envMarkers.contains("DEFINITELY_NOT_SET_XYZ"))
    }

    func testReadRefusesBadPids() {
        XCTAssertNil(ProcArgs.read(pid: 0, envKeys: []))
        XCTAssertNil(ProcArgs.read(pid: -5, envKeys: []))
        XCTAssertNil(ProcArgs.read(pid: 2_000_000_000, envKeys: []))
    }

    // MARK: MemoryReader

    func testFootprintOfSelfIsPositive() throws {
        XCTAssertGreaterThan(try XCTUnwrap(MemoryReader.footprint(pid: getpid())), 1_000_000)
        XCTAssertNil(MemoryReader.footprint(pid: 2_000_000_000))
    }

    // MARK: GitRootFinder

    private func tempTree() throws -> URL {
        let letters = String((0..<12).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("overstay-git-\(letters)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return base
    }

    private func makeDir(_ url: URL) throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }

    func testFindsNearestGitDirectoryAndCachesTheWalk() throws {
        let base = try tempTree()
        let root = base.appendingPathComponent("proj")
        try makeDir(root.appendingPathComponent(".git"))
        let deep = root.appendingPathComponent("a/b/c")
        try makeDir(deep)
        var cache: [String: String?] = [:]
        XCTAssertEqual(GitRootFinder.root(forCwd: deep.path, home: base.path, cache: &cache), root.path)
        XCTAssertEqual(cache[deep.path] ?? nil, root.path, "every visited directory is cached")
        XCTAssertEqual(cache[root.appendingPathComponent("a").path] ?? nil, root.path)
        // Served from the cache: the answer survives the .git entry disappearing.
        try FileManager.default.removeItem(at: root.appendingPathComponent(".git"))
        XCTAssertEqual(GitRootFinder.root(forCwd: deep.path, home: base.path, cache: &cache), root.path)
    }

    func testWorktreeGitFileCounts() throws {
        let base = try tempTree()
        let wt = base.appendingPathComponent("wt")
        try makeDir(wt.appendingPathComponent("src"))
        try Data("gitdir: elsewhere".utf8).write(to: wt.appendingPathComponent(".git"))
        var cache: [String: String?] = [:]
        XCTAssertEqual(GitRootFinder.root(forCwd: wt.appendingPathComponent("src").path, home: base.path, cache: &cache), wt.path)
    }

    func testNoGitMeansNilAndNegativeAnswersAreCached() throws {
        let base = try tempTree()
        let dir = base.appendingPathComponent("plain/deeper")
        try makeDir(dir)
        var cache: [String: String?] = [:]
        XCTAssertNil(GitRootFinder.root(forCwd: dir.path, home: base.path, cache: &cache))
        XCTAssertTrue(cache.keys.contains(dir.path), "a nil answer is cached as a nil value, not as a missing key")
    }

    func testNeverHomeItselfAndNeverSlash() throws {
        let base = try tempTree()
        try makeDir(base.appendingPathComponent(".git"))          // a dotfiles-style repo at home
        let sub = base.appendingPathComponent("sub")
        try makeDir(sub)
        var cache: [String: String?] = [:]
        XCTAssertNil(GitRootFinder.root(forCwd: sub.path, home: base.path, cache: &cache))
        XCTAssertNil(GitRootFinder.root(forCwd: base.path, home: base.path, cache: &cache))
        XCTAssertNil(GitRootFinder.root(forCwd: "/", home: base.path, cache: &cache))
        XCTAssertNil(GitRootFinder.root(forCwd: "", home: base.path, cache: &cache))
    }

    func testDepthLimitStopsTheWalk() throws {
        let base = try tempTree()
        try makeDir(base.appendingPathComponent("p/.git"))
        let deep = (0..<20).reduce(base.appendingPathComponent("p")) { dir, _ in dir.appendingPathComponent("d") }
        try makeDir(deep)
        var cache: [String: String?] = [:]
        XCTAssertNil(GitRootFinder.root(forCwd: deep.path, home: base.path, cache: &cache), "more than 16 levels up is not searched")
    }
}
