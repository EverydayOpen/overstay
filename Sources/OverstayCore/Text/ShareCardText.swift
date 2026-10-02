import Foundation

public enum ShareCardText {
    public static let sampleWatermark = "Sample data"

    /// From a scan: Ghosts only (Maybes are not part of any bulk action, so they are not "left running").
    public static func card(found: ScanResult, includeProjectNames: Bool, isSample: Bool) -> ShareCard {
        let groups = found.groups.filter { $0.ghostCount > 0 }
        return ShareCard(kind: .found, processCount: found.ghostCount, bytes: found.ghostBytes,
                         topAgents: top(groups.map { ($0.agent.displayName, $0.ghostBytes) }),
                         projectNames: includeProjectNames ? top(groups.compactMap { g in g.project.map { ($0.name, g.ghostBytes) } }) : [],
                         isSample: isSample, date: found.scannedAt)
    }

    /// From a stop: what actually exited.
    public static func card(stopped: StopOutcome, includeProjectNames: Bool, isSample: Bool) -> ShareCard {
        let done = stopped.results.filter { $0.status.wasStopped }.map(\.target)
        return ShareCard(kind: .stopped, processCount: done.count, bytes: stopped.heldBytes,
                         topAgents: top(done.map { ($0.agent.displayName, $0.footprintBytes) }),
                         projectNames: includeProjectNames ? top(done.compactMap { t in t.projectName.map { ($0, t.footprintBytes) } }) : [],
                         isSample: isSample, date: stopped.finishedAt)
    }

    /// "Your AI agents left 9.4 GB running."  /  "Stopped 183 leftovers. 9.4 GB was held."
    public static func headline(_ c: ShareCard) -> String {
        switch c.kind {
        case .found:
            return c.processCount == 0 ? "All quiet. Nothing left behind." : "Your AI agents left \(Format.bytes(c.bytes)) running."
        case .stopped:
            return c.processCount == 0 ? "Nothing was stopped."
                : "Stopped \(Format.count(c.processCount, "leftover")). \(Format.bytes(c.bytes)) was held."
        }
    }

    /// "183 leftover processes · Claude Code, Codex, Headless browsers" (+ " · foo, bar" when names are included)
    public static func subline(_ c: ShareCard) -> String {
        var parts = [Format.count(c.processCount, "leftover process")]
        if !c.topAgents.isEmpty { parts.append(c.topAgents.joined(separator: ", ")) }
        if !c.projectNames.isEmpty { parts.append(c.projectNames.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// Pasteboard fallback text: headline, subline, then `footer` (the caller passes the site address; Core has no URL).
    public static func plainText(_ c: ShareCard, footer: String) -> String {
        var lines = [headline(c), subline(c)]
        if c.isSample { lines.append(sampleWatermark) }
        if !footer.isEmpty { lines.append(footer) }
        return lines.joined(separator: "\n")
    }

    /// Names ranked by summed bytes (largest first, then name), unique, at most 3.
    private static func top(_ items: [(String, UInt64)]) -> [String] {
        var sum: [String: UInt64] = [:]
        for (n, b) in items { sum[n, default: 0] += b }
        return Array(sum.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(3).map(\.key))
    }
}
