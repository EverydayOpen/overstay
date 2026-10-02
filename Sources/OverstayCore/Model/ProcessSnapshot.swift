import Foundation

/// Which process incarnation this is. A reused pid has a different start time, so equal identities mean "same process".
/// `Signal.swift` re-reads this immediately before every signal and sends nothing unless it still equals the scanned one.
public struct ProcessIdentity: Codable, Hashable, Sendable {
    public var pid: Int32
    public var startSeconds: Int64
    public var startMicroseconds: Int32
    public var uid: UInt32
    /// `proc_pidpath` result; "" when unreadable.
    public var path: String

    public init(pid: Int32, startSeconds: Int64, startMicroseconds: Int32, uid: UInt32, path: String) {
        self.pid = pid
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
        self.uid = uid
        self.path = path
    }
}

/// State of the read end of a process's stdin pipe. `.unknown` unless the Mac layer could tell (BUILD_PLAN §5.4, VERIFY).
public enum StdinState: String, Codable, Sendable {
    case unknown
    case writerAlive
    case writerGone
}

/// One process as the Mac layer saw it. Pure data: Core never calls the system.
///
/// Privacy: `argv` is already scrubbed and capped (`Scrub.argv`) before it gets here, and environment values never
/// enter the model (only the names of allow-listed keys, in `envMarkers`). Processes of other users carry no
/// argv, cwd or footprint; they exist only so ancestry and session leaders can be resolved.
public struct ProcessSnapshot: Codable, Hashable, Sendable, Identifiable {
    public var pid: Int32
    public var ppid: Int32
    public var pgid: Int32
    /// `getsid(pid)`; nil when it failed.
    public var sid: Int32?
    public var uid: UInt32
    public var startSeconds: Int64
    public var startMicroseconds: Int32
    /// Full executable path; "" when unreadable.
    public var path: String
    /// Executable basename, or `pbi_name` / `pbi_comm` when the path is unreadable.
    public var name: String
    /// Scrubbed, capped argv (BUILD_PLAN §4.4). Empty when unreadable or another user's process.
    public var argv: [String]
    public var cwd: String?
    /// Nearest ancestor of `cwd` containing a `.git` entry (found with stat only); nil when none.
    public var projectRoot: String?
    /// `ri_phys_footprint`, the number Activity Monitor labels "Memory". 0 when unreadable.
    public var footprintBytes: UInt64
    /// Controlling terminal device (`e_tdev`); nil when there is none.
    public var ttyDevice: UInt32?
    /// `sid == pid`.
    public var isSessionLeader: Bool
    public var stdin: StdinState
    /// Names (never values) of allow-listed environment keys present (`EnvMarkers.allowed`).
    public var envMarkers: [String]

    public init(pid: Int32, ppid: Int32, pgid: Int32 = 0, sid: Int32? = nil, uid: UInt32,
                startSeconds: Int64, startMicroseconds: Int32 = 0, path: String, name: String? = nil,
                argv: [String] = [], cwd: String? = nil, projectRoot: String? = nil, footprintBytes: UInt64 = 0,
                ttyDevice: UInt32? = nil, isSessionLeader: Bool = false, stdin: StdinState = .unknown,
                envMarkers: [String] = []) {
        self.pid = pid
        self.ppid = ppid
        self.pgid = pgid
        self.sid = sid
        self.uid = uid
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
        self.path = path
        self.name = name ?? PathText.basename(path)
        self.argv = argv
        self.cwd = cwd
        self.projectRoot = projectRoot
        self.footprintBytes = footprintBytes
        self.ttyDevice = ttyDevice
        self.isSessionLeader = isSessionLeader
        self.stdin = stdin
        self.envMarkers = envMarkers
    }

    public var id: Int32 { pid }

    public var identity: ProcessIdentity {
        ProcessIdentity(pid: pid, startSeconds: startSeconds, startMicroseconds: startMicroseconds, uid: uid, path: path)
    }

    public var startDate: Date { Date(timeIntervalSince1970: Double(startSeconds) + Double(startMicroseconds) / 1_000_000) }

    /// Seconds since start, never negative.
    public func age(at now: Date) -> Int {
        let t = now.timeIntervalSince(startDate)
        return t > 0 ? Int(min(t, 1e12)) : 0 // NaN and negatives give 0, huge values are capped, nothing traps
    }

    /// One display line of the (already scrubbed) argv, at most 160 characters.
    public var argvSummary: String {
        let line = argv.joined(separator: " ")
        return line.count <= 160 ? line : String(line.prefix(159)) + "…"
    }
}

/// Path helpers that behave the same on Linux and macOS without NSString bridging.
public enum PathText {
    /// Process paths come from the kernel as real paths, so an entry typed through macOS's own symlinks (/tmp, /var, /etc)
    /// must be compared in its real form. Other symlinks are resolved by the app when the entry is added.
    public static func systemResolved(_ path: String) -> String {
        for d in ["/tmp", "/var", "/etc"] where path == d || path.hasPrefix(d + "/") { return "/private" + path }
        return path
    }

    /// Last path component; "" for "" and "/".
    public static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }
}
