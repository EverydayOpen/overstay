import Foundation

public enum Diagnostics {
    /// For Help > Copy Diagnostics (testers, T2). Plain text: counts (examined, argv/cwd/footprint readable, unreadable),
    /// the macOS version (passed in), then one block per signature-matching process, listed or not: tier, reason,
    /// signature id, executable basename, whether the parent is launchd, age bucket, project folder name, the names of
    /// environment markers present, and the scrubbed argv with "~" for home. No environment values, no pids, no full
    /// home path.
    public static func text(raw: RawScan, prefs: Preferences, now: Date, osVersion: String) -> String {
        let world = Scan.world(raw)
        let all = Classifier.classifyAll(world, prefs: prefs, now: now)
        let mine = all.map(\.process)
        let matched = all.filter { Signatures.match($0.process) != nil }
        var out = ["Overstay diagnostics", "macOS: \(osVersion)", ""]
        out.append("Examined: \(mine.count) of your processes (\(raw.processes.count) in total)")
        out.append("Readable: argv \(mine.filter { !$0.argv.isEmpty }.count), working folder \(mine.filter { $0.cwd != nil }.count), memory \(mine.filter { $0.footprintBytes > 0 }.count)")
        out.append("Unreadable: \(raw.unreadableCount)")
        out.append("Parent is launchd: \(mine.filter { $0.ppid == 1 }.count)")
        out.append("Signature matches: \(matched.count)")
        out.append("Age gate: \(prefs.ageGateMinutes) min")
        for (i, c) in matched.enumerated() {
            let p = c.process
            out.append("")
            out.append("[\(i + 1)] \(c.tier.rawValue)\(c.evidence.protectedReason.map { " (\($0))" } ?? "")")
            out.append("  why: \(c.why)")
            out.append("  signature: \(Signatures.match(p)?.id ?? "-")")
            out.append("  executable: \(p.name)")
            out.append("  parent is launchd: \(p.ppid == 1 ? "yes" : "no")")
            out.append("  age: \(bucket(p.age(at: now)))")
            out.append("  project: \(ProjectNamer.project(projectRoot: p.projectRoot, cwd: p.cwd, home: raw.home)?.name ?? "-")")
            if !p.envMarkers.isEmpty { out.append("  env markers (names only): \(p.envMarkers.joined(separator: ", "))") }
            out.append("  argv: \(home(p.argvSummary, raw.home))")
        }
        return out.joined(separator: "\n")
    }

    private static func bucket(_ seconds: Int) -> String {
        switch seconds {
        case ..<600: return "under 10 min"
        case ..<3600: return "under 1 hour"
        case ..<86_400: return "under 1 day"
        case ..<604_800: return "under 1 week"
        default: return "over 1 week"
        }
    }

    /// Replaces the home folder with "~" anywhere in the text (argv elements can hold paths in the middle).
    private static func home(_ s: String, _ home: String) -> String {
        guard !home.isEmpty, home != "/" else { return s }
        return s.replacingOccurrences(of: home + "/", with: "~/").replacingOccurrences(of: home, with: "~")
    }
}
