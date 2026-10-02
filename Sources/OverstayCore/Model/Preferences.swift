import Foundation

/// The few things the user can change. Named `Preferences` so it never collides with SwiftUI's `Settings` scene.
/// Stored as one JSON blob in UserDefaults (`App/AppModel.swift`, the only file that touches UserDefaults). Nothing here
/// can make Overstay touch more than the rules allow: `neverTouch` only adds to the protected list, and
/// `ageGateMinutes` has a floor.
public struct Preferences: Codable, Hashable, Sendable {
    /// A Ghost must have started at least this long ago. Default 10; the UI offers 10, 30 and 60; Core clamps to 1...1440.
    /// Tests move the clock forward instead of lowering this (BUILD_PLAN §6.3).
    public var ageGateMinutes: Int
    /// A Maybe younger than this many hours needs a per-item confirmation. Default 24.
    public var confirmYoungerThanHours: Int
    /// User additions to the protected list. Each entry is an executable basename ("postgres") or an absolute project
    /// root path. Matching a process by either makes it `.protected`. Never subtracts from the built-in list.
    public var neverTouch: [String]
    /// Off by default. A notification when Ghosts exceed `notifyThresholdBytes` (VERIFY from an unsigned app).
    public var notificationsEnabled: Bool
    public var notifyThresholdBytes: UInt64
    /// Puts folder names on the share card. Off by default.
    public var shareIncludesProjectNames: Bool
    /// Seconds between automatic scans while the app runs. 0 = manual only. Default 60.
    public var autoScanSeconds: Int
    public var hasSeenFirstRun: Bool

    public init(ageGateMinutes: Int = 10, confirmYoungerThanHours: Int = 24, neverTouch: [String] = [],
                notificationsEnabled: Bool = false, notifyThresholdBytes: UInt64 = 2 << 30,
                shareIncludesProjectNames: Bool = false, autoScanSeconds: Int = 60, hasSeenFirstRun: Bool = false) {
        self.ageGateMinutes = ageGateMinutes
        self.confirmYoungerThanHours = confirmYoungerThanHours
        self.neverTouch = neverTouch
        self.notificationsEnabled = notificationsEnabled
        self.notifyThresholdBytes = notifyThresholdBytes
        self.shareIncludesProjectNames = shareIncludesProjectNames
        self.autoScanSeconds = autoScanSeconds
        self.hasSeenFirstRun = hasSeenFirstRun
    }

    /// Every field is optional in a stored blob, so adding one later never wipes the user's protections.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = Preferences()
        ageGateMinutes = try c.decodeIfPresent(Int.self, forKey: .ageGateMinutes) ?? def.ageGateMinutes
        confirmYoungerThanHours = try c.decodeIfPresent(Int.self, forKey: .confirmYoungerThanHours) ?? def.confirmYoungerThanHours
        neverTouch = try c.decodeIfPresent([String].self, forKey: .neverTouch) ?? def.neverTouch
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? def.notificationsEnabled
        notifyThresholdBytes = try c.decodeIfPresent(UInt64.self, forKey: .notifyThresholdBytes) ?? def.notifyThresholdBytes
        shareIncludesProjectNames = try c.decodeIfPresent(Bool.self, forKey: .shareIncludesProjectNames) ?? def.shareIncludesProjectNames
        autoScanSeconds = try c.decodeIfPresent(Int.self, forKey: .autoScanSeconds) ?? def.autoScanSeconds
        hasSeenFirstRun = try c.decodeIfPresent(Bool.self, forKey: .hasSeenFirstRun) ?? def.hasSeenFirstRun
    }

    public static let `default` = Preferences()

    /// The age gate in seconds after clamping.
    public var ageGateSeconds: Int { min(max(ageGateMinutes, 1), 1440) * 60 }

    /// `confirmYoungerThanHours` in seconds, clamped to 0...1 year so a corrupt stored value cannot overflow.
    public var confirmYoungerThanSeconds: Int { min(max(confirmYoungerThanHours, 0), 8760) * 3600 }
}
