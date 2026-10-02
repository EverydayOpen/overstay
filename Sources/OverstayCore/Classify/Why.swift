import Foundation

public enum Why {
    /// One plain sentence group for the detail row, e.g.
    /// "Parent is gone. Looks like an MCP server. No live session in foo."  (Ghost)
    /// "Parent is gone. Looks like an MCP server. A live session is using foo, so it may still be needed."  (Maybe)
    /// "Parent is gone. Looks like an MCP server. Started 4 min ago, under the 10 min age gate."  (Maybe)
    /// "Parent is gone. Matches a generic pattern, so Overstay is not sure."  (Maybe)
    /// "Protected: inside an app bundle."  (protected)
    /// `gateSeconds` is only used for the "under the age gate" sentence.
    public static func line(_ e: SignalEvidence, tier: Classification, signatureTitle: String?, project: String?,
                            gateSeconds: Int? = nil) -> String {
        switch tier {
        case .protected: return "Protected: \(e.protectedReason ?? "on the protected list")."
        case .ignored: return e.signatureID == nil ? "Not a leftover." : "Not a leftover: its parent is still running."
        case .ghost, .maybe: break
        }
        var parts = ["Parent is gone."]
        let generic = e.signatureStrength == .generic
        if generic {
            parts.append("Matches a generic pattern, so Overstay is not sure.")
        } else if let t = signatureTitle {
            parts.append("Looks like \(phrase(t)).")
        }
        if tier == .ghost {
            parts.append(project.map { "No live session in \($0)." } ?? "No live session found.")
        } else {
            if !e.liveSessionPids.isEmpty {
                parts.append("A live session is using \(project ?? "this folder"), so it may still be needed.")
            }
            if e.networkServer { parts.append("It listens on the network, so it may be a server you started on purpose.") }
            if e.projectUnknown { parts.append("Its project could not be determined, so a live session cannot be ruled out.") }
            if !e.ageGateMet {
                let gate = gateSeconds.map { "the \(Format.age(seconds: $0)) age gate" } ?? "the age gate"
                parts.append("Started \(Format.age(seconds: e.ageSeconds)) ago, under \(gate).")
            }
            if e.stdin == .writerAlive { parts.append("Something still holds the other end of its input pipe.") }
        }
        return parts.joined(separator: " ")
    }

    private static let keepCase = ["MCP", "Playwright", "DevTools", "Vite", "webpack", "Next.js", "esbuild", "Codex", "Claude",
                                   "Cursor", "Gemini", "Aider", "Zed", "Windsurf", "VS"]

    /// "an MCP server", "a Playwright MCP server", "an automation browser".
    static func phrase(_ title: String) -> String {
        let first = title.split(separator: " ").first.map(String.init) ?? title
        let text = keepCase.contains(where: { first.hasPrefix($0) }) ? title : first.lowercased() + title.dropFirst(first.count)
        let vowel = text.first.map { "aeiouAEIOU".contains($0) } ?? false
        let article = text.hasPrefix("MCP") || vowel ? "an" : "a"
        return "\(article) \(text)"
    }
}
