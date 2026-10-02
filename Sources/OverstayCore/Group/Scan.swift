import Foundation

public enum Scan {
    /// RawScan -> classified, grouped, sorted ScanResult. Pure.
    public static func analyze(_ raw: RawScan, prefs: Preferences, now: Date) -> ScanResult {
        let world = World(raw)
        let all = Classifier.classifyAll(world, prefs: prefs, now: now)
        return ScanResult(scannedAt: raw.scannedAt, groups: Grouping.groups(all.filter { $0.tier.isListed }, home: raw.home),
                          examinedCount: all.count, unreadableCount: raw.unreadableCount, home: raw.home)
    }

    /// The same world `analyze` uses, for planning and diagnostics.
    public static func world(_ raw: RawScan) -> World { World(raw) }
}
