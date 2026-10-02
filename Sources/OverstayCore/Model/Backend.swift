import Foundation

/// The seam between the app and the system: a struct of closures with exactly two implementations.
/// `OverstayMac.LiveBackend.make()` reads and signals the real system; `DemoBackend.make(_:)` (Core, `Demo/`) serves a
/// fixture scenario and mutates an in-memory copy. In demo mode nothing is read from or signalled to the real system.
public struct Backend: Sendable {
    /// Lists processes. Never throws; unreadable things are counted in `RawScan.unreadableCount`.
    public var scan: @Sendable () async -> RawScan
    /// Runs a plan: re-verifies every target immediately before signalling it, signals leaf-first, waits the grace
    /// period, appends one activity line per target, and calls `progress` after each target. Never throws.
    public var stop: @Sendable (_ plan: StopPlan, _ prefs: Preferences, _ progress: @escaping @Sendable (TargetOutcome) -> Void) async -> StopOutcome
    /// The activity log, oldest first.
    public var loadLog: @Sendable () -> [ActivityEntry]
    /// True for the demo implementation: the window shows a "Sample data" badge and the share card is watermarked.
    public var isDemo: Bool

    public init(scan: @escaping @Sendable () async -> RawScan,
                stop: @escaping @Sendable (_ plan: StopPlan, _ prefs: Preferences, _ progress: @escaping @Sendable (TargetOutcome) -> Void) async -> StopOutcome,
                loadLog: @escaping @Sendable () -> [ActivityEntry], isDemo: Bool = false) {
        self.scan = scan
        self.stop = stop
        self.loadLog = loadLog
        self.isDemo = isDemo
    }
}

/// Launch scenarios for demo mode (BUILD_PLAN §9). Raw values are what `--demo <scenario>` and `OVERSTAY_DEMO` accept.
public enum DemoScenario: String, Codable, CaseIterable, Sendable {
    /// Nothing left behind: "All quiet."
    case quiet
    /// 183 Ghost processes, 9.4 GB, three groups (Claude Code, Codex, headless browsers), plus a few Maybes.
    case leftovers
    /// Only Maybes: shown, never pre-selected.
    case maybeOnly = "maybe-only"
    /// Like `leftovers`, but the fake signaller answers EPERM for one group.
    case refused
    /// Like `leftovers`, but some targets survive the polite signal, so "Force stop" appears.
    case survivors
    /// The first-run explanation screen over a quiet scan.
    case firstRun = "first-run"
}
