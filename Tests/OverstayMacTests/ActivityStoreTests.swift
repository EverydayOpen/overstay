import XCTest
import Darwin
import OverstayCore
@testable import OverstayMac

final class ActivityStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let letters = String((0..<12).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("overstay-log-\(letters)/Overstay")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        return dir
    }

    private func entry(_ pid: Int32, result: TargetStatus = .stopped) -> ActivityEntry {
        ActivityEntry(timestamp: Date(timeIntervalSince1970: 1_800_000_000), batchID: "b1", mode: .terminate, pid: pid,
                      executable: "node", signatureID: "mcp-server-named", agent: .claudeCode, project: "foo",
                      footprintBytes: 123_456_789, result: result, errno: nil, why: "Parent is gone.")
    }

    private func mode(_ url: URL) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) & 0o777
    }

    private func size(_ url: URL) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
    }

    func testPrepareCreatesPrivateFolderAndFile() throws {
        let dir = tempDir()
        try ActivityStore.prepare(in: dir)
        let file = dir.appendingPathComponent(ActivityLog.fileName)
        XCTAssertEqual(try mode(dir), 0o700)
        XCTAssertEqual(try mode(file), 0o600)
        try ActivityStore.prepare(in: dir)   // idempotent
        XCTAssertEqual(try size(file), 0)
    }

    func testPrepareTightensLooseModes() throws {
        let dir = tempDir()
        try ActivityStore.prepare(in: dir)
        let file = dir.appendingPathComponent(ActivityLog.fileName)
        XCTAssertEqual(chmod(dir.path, 0o755), 0)
        XCTAssertEqual(chmod(file.path, 0o644), 0)
        try ActivityStore.prepare(in: dir)
        XCTAssertEqual(try mode(dir), 0o700)
        XCTAssertEqual(try mode(file), 0o600)
    }

    func testAppendIsAppendOnlyAndRoundTrips() throws {
        let dir = tempDir()
        try ActivityStore.prepare(in: dir)
        let file = dir.appendingPathComponent(ActivityLog.fileName)
        // Something already in the file (another writer, an older version) is never overwritten.
        try Data("not json\n".utf8).write(to: file)
        XCTAssertEqual(chmod(file.path, 0o600), 0)
        var lastSize = try size(file)
        for pid in [101, 102, 103] as [Int32] {
            XCTAssertTrue(ActivityStore.append(entry(pid), in: dir))
            let now = try size(file)
            XCTAssertGreaterThan(now, lastSize)
            lastSize = now
        }
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("not json\n"))
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertEqual(text.split(separator: "\n").count, 4, "one line per entry")
        XCTAssertEqual(ActivityStore.load(in: dir).map(\.pid), [101, 102, 103], "oldest first, unreadable line skipped")
        XCTAssertEqual(try mode(file), 0o600)
    }

    func testLineHoldsNoArgvEnvOrPath() throws {
        let dir = tempDir()
        try ActivityStore.prepare(in: dir)
        ActivityStore.append(entry(7), in: dir)
        let text = try String(contentsOf: dir.appendingPathComponent(ActivityLog.fileName), encoding: .utf8)
        XCTAssertFalse(text.contains("/Users/"))
        XCTAssertFalse(text.contains("argv"))
        XCTAssertTrue(text.contains("\"project\":\"foo\""))
    }

    func testMissingFolderOrFileIsEmptyAndAppendFails() {
        let dir = tempDir()
        XCTAssertEqual(ActivityStore.load(in: dir), [])
        XCTAssertFalse(ActivityStore.append(entry(1), in: dir), "append never creates the folder: prepare does")
    }

    func testSymlinkedLogIsRefused() throws {
        let dir = tempDir()
        try ActivityStore.prepare(in: dir)
        let elsewhere = dir.deletingLastPathComponent().appendingPathComponent("elsewhere.txt")
        try Data("keep".utf8).write(to: elsewhere)
        let file = dir.appendingPathComponent(ActivityLog.fileName)
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(symlink(elsewhere.path, file.path), 0)
        XCTAssertThrowsError(try ActivityStore.prepare(in: dir))
        XCTAssertFalse(ActivityStore.append(entry(1), in: dir))
        XCTAssertEqual(try String(contentsOf: elsewhere, encoding: .utf8), "keep")
    }

    func testSymlinkedFolderIsRefused() throws {
        let real = tempDir()
        try ActivityStore.prepare(in: real)
        let link = real.deletingLastPathComponent().appendingPathComponent("link")
        XCTAssertEqual(symlink(real.path, link.path), 0)
        XCTAssertThrowsError(try ActivityStore.prepare(in: link))
    }

    func testFolderThatIsAFileIsRefused() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir)
        XCTAssertThrowsError(try ActivityStore.prepare(in: dir))
    }

    func testDefaultDirectoryIsUnderApplicationSupport() {
        XCTAssertTrue(ActivityStore.directory.path.hasSuffix("/Library/Application Support/Overstay"))
    }
}
