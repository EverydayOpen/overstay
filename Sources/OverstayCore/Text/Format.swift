import Foundation

public enum Format {
    /// Binary units labelled as Activity Monitor does: "412 MB", "9.4 GB" (one decimal below 100 GB), "0 KB".
    public static func bytes(_ n: UInt64) -> String {
        let kb = Double(n) / 1024
        if kb < 1024 { return "\(Int(kb.rounded(.down))) KB" }
        let mb = Int((kb / 1024).rounded())
        if mb < 1024 { return "\(mb) MB" }
        let gb = Double(n) / 1_073_741_824
        if gb < 1024 { return unit(gb, "GB") }
        return unit(gb / 1024, "TB")
    }

    private static func unit(_ v: Double, _ name: String) -> String {
        if v >= 100 { return "\(Int(v.rounded())) \(name)" }
        let tenths = Int((v * 10).rounded())
        return "\(tenths / 10).\(tenths % 10) \(name)"
    }

    /// "just now", "12 min", "3 hours", "3 days"
    public static func age(seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60) min" }
        if s < 86_400 { return plural(s / 3600, "hour") }
        return plural(s / 86_400, "day")
    }

    /// "started 3 days ago". Never "ended": we cannot know when a session ended.
    public static func started(seconds: Int) -> String {
        let a = age(seconds: seconds)
        return a == "just now" ? "started just now" : "started \(a) ago"
    }

    /// "1 process", "183 processes"
    public static func count(_ n: Int, _ noun: String) -> String { "\(n) \(n == 1 ? noun : pluralForm(noun))" }

    private static func plural(_ n: Int, _ noun: String) -> String { "\(n) \(n == 1 ? noun : noun + "s")" }

    private static func pluralForm(_ noun: String) -> String {
        if noun.hasSuffix("s") || noun.hasSuffix("x") || noun.hasSuffix("ch") || noun.hasSuffix("sh") { return noun + "es" }
        if noun.hasSuffix("y"), let before = noun.dropLast().last, !"aeiou".contains(before) { return String(noun.dropLast()) + "ies" }
        return noun + "s"
    }
}
