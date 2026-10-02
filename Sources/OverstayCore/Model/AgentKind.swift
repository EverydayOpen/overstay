/// Which AI coding tool a process most likely belongs to. These names appear only descriptively, as things Overstay
/// detects (BUILD_PLAN §1, naming rule); `displayName` is what the UI and share card print.
public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claudeCode
    case codex
    case cursor
    case zed
    case windsurf
    case vscode
    case gemini
    /// Playwright, Puppeteer or DevTools-driven Chrome-for-Testing / Chromium. Never the user's normal Chrome.
    case automationBrowser
    /// A tool server (usually MCP) whose agent can't be told once its parent is gone.
    case unattributed

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .zed: "Zed"
        case .windsurf: "Windsurf"
        case .vscode: "VS Code agents"
        case .gemini: "Gemini CLI"
        case .automationBrowser: "Headless browsers"
        case .unattributed: "Agent tool servers"
        }
    }
}
