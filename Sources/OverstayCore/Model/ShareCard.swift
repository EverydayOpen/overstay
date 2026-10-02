import Foundation

/// The data behind the 1200x630 "Copy my number" card. No paths and no project names unless the user ticked
/// "include project names" (`projectNames` is empty otherwise). `ShareCardText` builds it and prints the words.
public struct ShareCard: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// "Your AI agents left 9.4 GB running." Built from a scan.
        case found
        /// "Stopped 183 leftovers. 9.4 GB was held." Built from a stop outcome.
        case stopped
    }

    public var kind: Kind
    public var processCount: Int
    public var bytes: UInt64
    /// Agent display names, largest first, at most 3.
    public var topAgents: [String]
    /// Folder names, largest first, at most 3; empty unless included.
    public var projectNames: [String]
    /// Draws the "Sample data" watermark. Always true in demo mode.
    public var isSample: Bool
    public var date: Date

    public init(kind: Kind, processCount: Int, bytes: UInt64, topAgents: [String], projectNames: [String] = [],
                isSample: Bool = false, date: Date) {
        self.kind = kind
        self.processCount = processCount
        self.bytes = bytes
        self.topAgents = topAgents
        self.projectNames = projectNames
        self.isSample = isSample
        self.date = date
    }
}
