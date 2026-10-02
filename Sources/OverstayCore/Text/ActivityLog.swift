import Foundation

/// The wire format of `activity.jsonl`: one JSON object per line, append-only. No argv, no environment, no full paths
/// (`ActivityEntry` has no field that could carry them).
public enum ActivityLog {
    public static let fileName = "activity.jsonl"

    /// One line, no trailing newline, sorted keys, ISO-8601 dates (whole seconds).
    public static func encode(_ e: ActivityEntry) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(e) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(line: String) -> ActivityEntry? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(ActivityEntry.self, from: Data(line.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
    }

    /// Tolerant: blank lines ignored, unreadable lines counted, never throws.
    public static func decodeAll(_ text: String) -> (entries: [ActivityEntry], skippedLines: Int) {
        var entries: [ActivityEntry] = []
        var skipped = 0
        for raw in text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            if raw.allSatisfy(\.isWhitespace) { continue }
            if let e = decode(line: String(raw)) { entries.append(e) } else { skipped += 1 }
        }
        return (entries, skipped)
    }
}
