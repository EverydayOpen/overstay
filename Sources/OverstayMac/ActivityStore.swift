import Darwin
import Foundation
import OverstayCore

/// The activity log: JSONL, append-only, file 0600 in a 0700 folder under ~/Library/Application Support/Overstay.
/// The only file Overstay writes besides a share-card PNG the user saves, and the only file it reads (BUILD_PLAN §3).
/// Each call takes the folder so tests can use a temp one; production always uses the default.
enum ActivityStore {
    static var directory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Overstay", isDirectory: true)
    }

    /// Creates the folder (0700) and file (0600) if needed and proves we can append. Throws -> the stop is refused (§3 rule 14).
    static func prepare(in dir: URL = directory) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var st = stat()
        // lstat: a symlink or someone else's folder is refused rather than followed.
        guard lstat(dir.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, st.st_uid == getuid() else {
            throw POSIXError(.ENOTDIR)
        }
        if (st.st_mode & 0o777) != 0o700, chmod(dir.path, 0o700) != 0 { throw posix() }
        let fd = try openLog(in: dir)
        close(fd)
    }

    /// One line, one write(2). False on any failure; the stop then refuses to signal anything further.
    @discardableResult
    static func append(_ entry: ActivityEntry, in dir: URL = directory) -> Bool {
        guard let fd = try? openLog(in: dir) else { return false }
        defer { close(fd) }
        let bytes = Array((ActivityLog.encode(entry) + "\n").utf8)
        var done = 0
        while done < bytes.count {
            let n = bytes[done...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                return false
            }
            done += n
        }
        return true
    }

    /// Oldest first. Missing or unreadable file = empty. ponytail: reads the whole file; paginate if logs reach megabytes.
    static func load(in dir: URL = directory) -> [ActivityEntry] {
        guard let text = try? String(contentsOf: dir.appendingPathComponent(ActivityLog.fileName), encoding: .utf8) else { return [] }
        return ActivityLog.decodeAll(text).entries
    }

    // MARK: -

    /// O_NOFOLLOW (no symlink), O_NONBLOCK (a planted FIFO fails instead of hanging), then the opened file itself is
    /// checked: a regular file of ours, mode forced to 0600.
    private static func openLog(in dir: URL) throws -> Int32 {
        let path = dir.appendingPathComponent(ActivityLog.fileName).path
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw posix() }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == getuid() else {
            close(fd)
            throw POSIXError(.EPERM)
        }
        if (st.st_mode & 0o777) != 0o600, fchmod(fd, 0o600) != 0 {
            close(fd)
            throw posix()
        }
        return fd
    }

    private static func posix() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
