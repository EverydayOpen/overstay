import Foundation

/// The detection table. Plain data: adding a signature is one line here plus one row in `SignatureTests`.
/// Order matters, first match wins: session roots first (so a Claude Code `mcp serve` is a session, never an MCP server),
/// then specific entries, then generic ones. Every shape here is VERIFY against tester dumps (BUILD_PLAN §12); the MCP
/// shapes come from the upstream reports (stdio servers such as `chroma-mcp`, `cli-mcp-server`, `context7-mcp`, and
/// `codex app-server --listen stdio://` helpers), the rest from each tool's published package and binary names.
/// v1 only sees orphans (parent is launchd): a leak whose parent is still alive (openai/codex#25744) is out of scope, and
/// so are `docker run -i mcp/...` servers (the docker CLI is protected by name). There is no Cursor or Zed worker row
/// until a tester dump shows what they leave behind.
public enum Signatures {
    public static let all: [Signature] = [
        // Session roots and IDE hosts: never listed, protected, and while one runs its project has a live session.
        Signature("claude-session", "Claude Code session", kind: .agentRoot, agent: .claudeCode,
                  [.tokenContains("@anthropic-ai/claude-code"), .nameEquals("claude"), .tokenBaseEquals("claude"),
                   .pathContains("/claude/versions/")]),
        // Helper of the Codex app, specific to its stdio listener (VERIFY: may live inside the app bundle, then it is protected).
        // A `--listen ws://...` server is on purpose, so it falls through to the protected codex-session row.
        Signature("codex-app-server", "Codex helper", kind: .agentWorker, agent: .codex,
                  [.all([.nameEquals("codex"), .tokenBaseEquals("app-server"), .tokenContains("stdio://")])]),
        Signature("codex-session", "Codex session", kind: .agentRoot, agent: .codex,
                  [.tokenContains("@openai/codex"), .nameEquals("codex"), .tokenBaseEquals("codex")]),
        Signature("gemini-session", "Gemini CLI session", kind: .agentRoot, agent: .gemini,
                  [.tokenContains("@google/gemini-cli"), .nameEquals("gemini"), .tokenBaseEquals("gemini")]),
        Signature("cursor-agent-session", "Cursor Agent session", kind: .agentRoot, agent: .cursor,
                  [.nameEquals("cursor-agent"), .tokenBaseEquals("cursor-agent")]),
        Signature("aider-session", "Aider session", kind: .agentRoot,
                  [.nameEquals("aider"), .tokenBaseEquals("aider")]),
        Signature("cursor-host", "Cursor", kind: .agentRoot, agent: .cursor, [.pathContains("/Cursor.app/")]),
        Signature("zed-host", "Zed", kind: .agentRoot, agent: .zed, [.pathContains("/Zed.app/")]),
        Signature("windsurf-host", "Windsurf", kind: .agentRoot, agent: .windsurf, [.pathContains("/Windsurf.app/")]),
        Signature("vscode-host", "VS Code", kind: .agentRoot, agent: .vscode, [.pathContains("/Visual Studio Code")]),
        Signature("codex-host", "Codex", kind: .agentRoot, agent: .codex, [.pathContains("/Codex.app/")]),

        // Tool servers that outlive their agent. Names seen in the upstream reports are covered by the "-mcp" suffix.
        Signature("mcp-official", "MCP server", kind: .mcpServer, [.tokenContains("@modelcontextprotocol/server-")]),
        Signature("playwright-mcp", "Playwright MCP server", kind: .mcpServer,
                  [.tokenContains("@playwright/mcp"), .tokenBaseEquals("playwright-mcp")]),
        Signature("chrome-devtools-mcp", "DevTools MCP server", kind: .mcpServer, [.tokenContains("chrome-devtools-mcp")]),
        Signature("mcp-server-named", "MCP server", kind: .mcpServer,
                  [.tokenBasePrefix("mcp-server-"), .tokenBasePrefix("mcp_server_"), .tokenBaseSuffix("-mcp-server"),
                   .tokenBaseEquals("mcp-server"), .tokenBaseEquals("mcp-remote")]),
        Signature("mcp-suffix", "MCP server", kind: .mcpServer, [.tokenBaseSuffix("-mcp")]),
        // Seen in the Codex report (VERIFY the real argv): helpers of the Codex app.
        Signature("codex-node-repl", "Codex helper", kind: .agentWorker, agent: .codex, [.nameEquals("node_repl")]),
        Signature("codex-computer-use", "Codex helper", kind: .agentWorker, agent: .codex,
                  [.all([.nameEquals("SkyComputerUseClient"), .tokenBaseEquals("mcp")])]),

        // Automation browsers. The user's normal Chrome never matches: every pattern needs an automation marker.
        Signature("automation-chrome", "Automation browser", kind: .automationBrowser, agent: .automationBrowser,
                  [.all([.pathContains("Chrome for Testing"), .flag("--headless")]),
                   .all([.pathContains("Chrome for Testing"), .flag("--remote-debugging-pipe")]),
                   .all([.pathContains("/ms-playwright/"), .flag("--remote-debugging-pipe")]),
                   // Default Playwright MCP launches the user's installed Chrome with its own profile (VERIFY the argv on a real dump).
                   // `Contents/MacOS/` keeps this to the main process; helpers live under Frameworks/.../Helper.app.
                   .all([.pathContains("Google Chrome.app/Contents/MacOS/"), .tokenContains("/ms-playwright/"), .flag("--remote-debugging-pipe")]),
                   .all([.pathContains("Google Chrome.app/Contents/MacOS/"), .tokenContains("playwright_chromiumdev_profile"), .flag("--remote-debugging-pipe")]),
                   .all([.pathContains("/.cache/puppeteer/"), .flag("--headless")]),
                   .all([.pathContains("Google Chrome.app"), .tokenContains("/chrome-devtools-mcp/"), .flag("--remote-debugging-pipe")]),
                   .nameEquals("chrome-headless-shell")]),

        // Generic: shown as Maybe at best, never pre-selected.
        Signature("mcp-bare", "Possible MCP server", kind: .mcpServer, strength: .generic, [.tokenBaseEquals("mcp")]),
        Signature("dev-vite", "Dev server (Vite)", kind: .devTool, strength: .generic, [.tokenBaseEquals("vite")]),
        Signature("dev-webpack", "Dev server (webpack)", kind: .devTool, strength: .generic,
                  [.tokenBaseEquals("webpack-dev-server")]),
        Signature("dev-next", "Dev server (Next.js)", kind: .devTool, strength: .generic, [.tokenBasePrefix("next-server")]),
        Signature("dev-esbuild", "Build service (esbuild)", kind: .devTool, strength: .generic,
                  [.all([.nameEquals("esbuild"), .flag("--service")])]),
    ]

    /// First matching signature in table order. Session-root and MCP patterns see the whole argv only for launchers (node,
    /// python, a shell...); any other program is judged by its own argv[0] and path, so `vim mcp-server-notes.md` or
    /// `grep claude x` never match. The other kinds are anchored on a name or path already.
    public static func match(_ p: ProcessSnapshot) -> Signature? {
        let wide = Matching.isLauncher(p)
        let own = Array(p.argv.prefix(1)) + [p.path]
        // npm rewrites its process title, so a wrapper's argv[0] is one string (`npm exec @scope/pkg-mcp@latest`): split it
        // so the token-base patterns see each word, as they do for the script string of `sh -c`.
        var argv = p.argv
        if wide, let f = argv.first {
            let words = f.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if words.count > 1 { argv = words + argv.dropFirst() }
        }
        let head = wide ? Matching.scriptHead(argv) : nil
        let command = wide ? Matching.commandHead(argv) : nil
        for s in all {
            let tokens = (wide || (s.kind != .agentRoot && s.kind != .mcpServer)) ? argv : own
            // Session roots read names from the command only (`npx server-x <dir>/claude` is not a session); their package
            // patterns (`tokenContains`) still see all of `tokens`.
            let h = s.kind == .agentRoot ? command : head
            if s.patterns.contains(where: { Matching.matches($0, p, tokens: tokens, head: h) }) { return s }
        }
        return nil
    }
}

public enum Matching {
    static let scriptSuffixes = [".js", ".mjs", ".cjs", ".ts", ".py"]
    static let launchers: Set<String> = ["node", "nodejs", "bun", "bunx", "deno", "npm", "npx", "pnpm", "pnpx", "yarn",
                                         "uv", "uvx", "pipx", "tsx", "ts-node", "sh", "bash", "zsh", "dash"]

    /// Last path component of the token's first word, a trailing `@version` and a trailing .js .mjs .cjs .ts .py removed.
    /// (First word only, so `sh -c "mcp-server-x /dir"` still reads as `mcp-server-x`.)
    public static func base(_ token: String) -> String {
        let word = token.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? token
        var b = PathText.basename(word)
        if let at = b.dropFirst().firstIndex(of: "@") { b = String(b[..<at]) }
        for s in scriptSuffixes where b.hasSuffix(s) && b.count > s.count {
            b.removeLast(s.count)
            break
        }
        return b
    }

    /// A runtime or shell that starts other programs by name. Only these have their whole argv searched.
    public static func isLauncher(_ p: ProcessSnapshot) -> Bool {
        let n = p.name.lowercased()
        return launchers.contains(n) || n.hasPrefix("python")
    }

    /// argv up to and including the first script (index >= 1, a .js .mjs .cjs .ts .py path). Whatever follows is that
    /// script's own arguments, so a `node build.js mcp-server-x` job never reads as a server. A launcher without a script
    /// (`npx -y pkg`, `python -m pkg`, `node .bin/tool`) keeps its whole argv.
    static func scriptHead(_ argv: [String]) -> [String] {
        let isScript = { (t: String) -> Bool in
            let b = PathText.basename(t).lowercased()
            return scriptSuffixes.contains { b.hasSuffix($0) }
        }
        guard let i = argv.indices.dropFirst().first(where: { isScript(argv[$0]) }) else { return argv }
        return Array(argv[...i])
    }

    /// argv[0] plus the first later entry that is not a flag: the program a launcher starts (`npx -y pkg` -> `pkg`,
    /// `sh -c "claude x"` -> the script string). Known limit: `npx --package x claude` reads as `x`.
    static func commandHead(_ argv: [String]) -> [String] {
        Array(argv.prefix(1)) + Array(argv.dropFirst().first { !$0.hasPrefix("-") }.map { [$0] } ?? [])
    }

    public static func matches(_ pattern: Pattern, _ p: ProcessSnapshot) -> Bool { matches(pattern, p, tokens: p.argv) }

    /// `head` (default `tokens`) is what the token-base patterns see; `tokenContains` and `flag` see all of `tokens`.
    static func matches(_ pattern: Pattern, _ p: ProcessSnapshot, tokens: [String], head: [String]? = nil) -> Bool {
        let bases = head ?? tokens
        switch pattern {
        case .tokenContains(let s): return tokens.contains { $0.contains(s) }
        case .tokenBaseEquals(let s): return bases.contains { base($0) == s }
        case .tokenBasePrefix(let s): return bases.contains { base($0).hasPrefix(s) }
        case .tokenBaseSuffix(let s): return bases.contains { base($0).hasSuffix(s) }
        case .flag(let f): return tokens.contains { $0 == f || $0.hasPrefix(f + "=") }
        case .pathContains(let s): return p.path.contains(s)
        case .nameEquals(let s): return p.name == s
        case .all(let ps): return !ps.isEmpty && ps.allSatisfy { matches($0, p, tokens: tokens, head: head) }
        }
    }
}
