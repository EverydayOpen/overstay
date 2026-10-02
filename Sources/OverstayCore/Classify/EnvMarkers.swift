import Foundation

public enum EnvMarkers {
    /// The only environment keys the Mac layer may look at. Names only ever leave the Mac layer, never values.
    /// Both are unverified (VERIFY against tester dumps); the classifier does not depend on them.
    public static let allowed: [String] = ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"]

    public static func agent(for marker: String) -> AgentKind? {
        switch marker {
        case "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT": return .claudeCode
        default: return nil
        }
    }
}
