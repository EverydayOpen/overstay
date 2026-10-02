import Foundation

/// What the Mac layer hands to Core: every process it could list, plus who and where we are.
/// Other users' processes carry only identity and parentage (no argv, cwd or footprint).
public struct RawScan: Codable, Hashable, Sendable {
    public var processes: [ProcessSnapshot]
    public var selfPid: Int32
    public var uid: UInt32
    /// The user's home directory, to print `~/dev/foo` and to stop project detection there.
    public var home: String
    public var scannedAt: Date
    /// Same-user processes whose argv, cwd or footprint the system refused to give (hardened processes, races).
    public var unreadableCount: Int

    public init(processes: [ProcessSnapshot], selfPid: Int32, uid: UInt32, home: String, scannedAt: Date,
                unreadableCount: Int = 0) {
        self.processes = processes
        self.selfPid = selfPid
        self.uid = uid
        self.home = home
        self.scannedAt = scannedAt
        self.unreadableCount = unreadableCount
    }
}

/// The classified, grouped view the UI shows. Built by `Scan.analyze` (pure).
public struct ScanResult: Codable, Hashable, Sendable {
    public var scannedAt: Date
    /// Only groups with at least one Ghost or Maybe, largest Ghost footprint first.
    public var groups: [LeftoverGroup]
    /// Same-user processes looked at (so "nothing found" can say what it checked).
    public var examinedCount: Int
    public var unreadableCount: Int
    public var home: String

    public init(scannedAt: Date, groups: [LeftoverGroup], examinedCount: Int, unreadableCount: Int = 0, home: String = "") {
        self.scannedAt = scannedAt
        self.groups = groups
        self.examinedCount = examinedCount
        self.unreadableCount = unreadableCount
        self.home = home
    }

    public var ghostCount: Int { groups.reduce(0) { $0 + $1.ghostCount } }
    public var maybeCount: Int { groups.reduce(0) { $0 + $1.maybeCount } }
    public var ghostBytes: UInt64 { groups.reduce(0) { $0 + $1.ghostBytes } }
    /// "All quiet": nothing to show, not even a Maybe.
    public var isQuiet: Bool { groups.isEmpty }
}
