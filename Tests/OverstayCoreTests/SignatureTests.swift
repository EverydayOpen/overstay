import Foundation
import XCTest
@testable import OverstayCore

final class SignatureTests: XCTestCase {
    private struct Row {
        var id: String
        var hit: ProcessSnapshot
        var miss: ProcessSnapshot
    }

    private func node(_ args: String..., name: String = "node") -> ProcessSnapshot {
        Fx.proc(500, path: "/usr/local/bin/\(name)", argv: [name] + args)
    }

    private func chrome(_ flags: String..., path: String) -> ProcessSnapshot {
        Fx.proc(500, path: path, argv: [PathText.basename(path)] + flags, cwd: "/", root: nil)
    }

    /// One positive and one near-miss per signature. Adding a signature without a row here fails `testEverySignatureHasARow`.
    private var rows: [Row] {
        [
            Row(id: "claude-session", hit: Fx.proc(500, path: "/Users/jane/.local/share/claude/versions/2.1.0", name: "claude", argv: ["claude"]),
                miss: node("/x/other-cli.js")),
            Row(id: "codex-app-server", hit: Fx.proc(500, path: "/usr/local/bin/codex", argv: ["codex", "app-server", "--listen", "stdio://"]),
                miss: Fx.proc(500, path: "/usr/local/bin/codex", argv: ["codex", "app-server", "--analytics-default-enabled"])),
            Row(id: "codex-session", hit: node("/usr/local/lib/node_modules/@openai/codex/bin/codex.js"), miss: node("/x/codec.js")),
            Row(id: "gemini-session", hit: node("/usr/local/lib/node_modules/@google/gemini-cli/dist/index.js"), miss: node("/x/gem.js")),
            Row(id: "cursor-agent-session", hit: Fx.proc(500, path: "/Users/jane/.local/bin/cursor-agent", argv: ["cursor-agent"]),
                miss: Fx.proc(500, path: "/usr/bin/grep", argv: ["grep", "cursor-agent", "notes.txt"])),
            Row(id: "aider-session", hit: Fx.proc(500, path: "/usr/local/bin/python3", argv: ["python3", "/usr/local/bin/aider"]),
                miss: Fx.proc(500, path: "/usr/bin/less", argv: ["less", "aider"])),
            Row(id: "cursor-host", hit: Fx.proc(500, path: "/Applications/Cursor.app/Contents/MacOS/Cursor", argv: ["Cursor"]),
                miss: Fx.proc(500, path: "/Applications/Cursory.app/Contents/MacOS/Cursory", argv: ["Cursory"])),
            Row(id: "zed-host", hit: Fx.proc(500, path: "/Applications/Zed.app/Contents/MacOS/zed", argv: ["zed"]),
                miss: Fx.proc(500, path: "/Applications/Zedd.app/Contents/MacOS/zedd", argv: ["zedd"])),
            Row(id: "windsurf-host", hit: Fx.proc(500, path: "/Applications/Windsurf.app/Contents/MacOS/Windsurf", argv: ["Windsurf"]),
                miss: Fx.proc(500, path: "/Applications/Windsurfer.app/Contents/MacOS/x", argv: ["x"])),
            Row(id: "vscode-host", hit: Fx.proc(500, path: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron", argv: ["Code"]),
                miss: Fx.proc(500, path: "/Applications/Visual Studio.app/Contents/MacOS/x", argv: ["x"])),
            Row(id: "codex-host", hit: Fx.proc(500, path: "/Applications/Codex.app/Contents/MacOS/Codex", argv: ["Codex"]),
                miss: Fx.proc(500, path: "/Applications/Codexx.app/Contents/MacOS/x", argv: ["x"])),
            Row(id: "mcp-official", hit: node("/Users/jane/.npm/_npx/ab/node_modules/@modelcontextprotocol/server-filesystem/dist/index.js", "/Users/jane/dev/foo"),
                miss: node("/x/@modelcontextprotocol/sdk/index.js")),
            Row(id: "playwright-mcp", hit: node("/Users/jane/.npm/_npx/ab/node_modules/@playwright/mcp/cli.js"),
                miss: node("/x/@playwright/test/cli.js")),
            Row(id: "chrome-devtools-mcp", hit: node("/Users/jane/.npm/_npx/ab/node_modules/chrome-devtools-mcp/build/src/index.js"),
                miss: node("/x/chrome-devtools-protocol/index.js")),
            Row(id: "mcp-server-named", hit: node("/Users/jane/.npm/_npx/ab/node_modules/.bin/mcp-server-git"),
                miss: node("/x/mcp-servers/index.js")),
            Row(id: "mcp-suffix", hit: node("/Users/jane/.npm/_npx/ab/node_modules/.bin/context7-mcp"), miss: node("/x/mcp-core/index.js")),
            Row(id: "codex-node-repl", hit: Fx.proc(500, path: "/x/node_repl", argv: ["node_repl"]),
                miss: Fx.proc(500, path: "/usr/local/bin/node", argv: ["node", "repl"])),
            Row(id: "codex-computer-use", hit: Fx.proc(500, path: "/x/SkyComputerUseClient", argv: ["SkyComputerUseClient", "mcp"]),
                miss: Fx.proc(500, path: "/x/SkyComputerUseClient", argv: ["SkyComputerUseClient", "serve"])),
            Row(id: "automation-chrome",
                hit: chrome("--headless=new", "--remote-debugging-pipe", path: "/Users/jane/.cache/puppeteer/chrome/mac-1/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"),
                miss: chrome("--new-window", path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")),
            Row(id: "mcp-bare", hit: node("/opt/tools/bin/mcp"), miss: node("/opt/tools/bin/mcpx")),
            Row(id: "dev-vite", hit: node("/Users/jane/dev/foo/node_modules/.bin/vite", "--port", "5173"), miss: node("/x/vitest.js")),
            Row(id: "dev-webpack", hit: node("/Users/jane/dev/foo/node_modules/.bin/webpack-dev-server"), miss: node("/x/webpack.js")),
            Row(id: "dev-next", hit: Fx.proc(500, path: "/usr/local/bin/node", argv: ["next-server (v14.2.3)"]), miss: node("/x/next.js")),
            Row(id: "dev-esbuild", hit: Fx.proc(500, path: "/x/node_modules/@esbuild/darwin-arm64/bin/esbuild", argv: ["esbuild", "--service=0.19.2", "--ping"]),
                miss: Fx.proc(500, path: "/x/esbuild", argv: ["esbuild", "app.js"])),
        ]
    }

    func testEverySignatureHasARow() {
        XCTAssertEqual(Set(rows.map(\.id)), Set(Signatures.all.map(\.id)))
        XCTAssertEqual(Signatures.all.count, Set(Signatures.all.map(\.id)).count, "ids are unique")
    }

    func testEverySignatureMatchesItsPositiveAndNotItsNearMiss() {
        for r in rows {
            XCTAssertEqual(Signatures.match(r.hit)?.id, r.id, "hit for \(r.id)")
            XCTAssertNotEqual(Signatures.match(r.miss)?.id, r.id, "near miss for \(r.id)")
        }
    }

    func testScrubbingNeverBreaksADetection() {
        for r in rows {
            var scrubbed = r.hit
            scrubbed.argv = Scrub.argv(r.hit.argv)
            XCTAssertEqual(scrubbed.argv, r.hit.argv, "scrub changed the argv for \(r.id)")
            XCTAssertEqual(Signatures.match(scrubbed)?.id, r.id)
        }
    }

    func testIdsAreLowercaseHyphenated() {
        for s in Signatures.all { XCTAssertNotNil(s.id.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression), s.id) }
    }

    func testSpecificEntriesComeBeforeGenericOnes() {
        let strengths = Signatures.all.map(\.strength)
        let firstGeneric = strengths.firstIndex(of: .generic)!
        XCTAssertFalse(strengths[firstGeneric...].contains(.specific))
    }

    func testSessionRootsComeBeforeEveryToolServerPattern() {
        let lastRoot = Signatures.all.lastIndex { $0.kind == .agentRoot }!
        let firstServer = Signatures.all.firstIndex { $0.kind == .mcpServer }!
        XCTAssertLessThan(lastRoot, firstServer)
    }

    func testOnlyLaunchersAreSearchedForTokens() {
        XCTAssertNil(Signatures.match(Fx.proc(500, path: "/usr/bin/vim", argv: ["vim", "mcp-server-notes.md"])))
        XCTAssertNil(Signatures.match(Fx.proc(500, path: "/usr/bin/grep", argv: ["grep", "-r", "@modelcontextprotocol/server-", "."])))
        XCTAssertEqual(Signatures.match(Fx.proc(500, path: "/opt/homebrew/bin/uvx", argv: ["uvx", "mcp-server-git"]))?.id, "mcp-server-named")
        XCTAssertEqual(Signatures.match(Fx.proc(500, path: "/usr/bin/python3", argv: ["python3", "-m", "mcp_server_git"]))?.id, "mcp-server-named")
        XCTAssertEqual(Signatures.match(Fx.proc(500, path: "/bin/sh", argv: ["sh", "-c", "mcp-server-time /Users/jane/x"]))?.id, "mcp-server-named")
        // A self-named binary is found by its own argv[0] or path.
        XCTAssertEqual(Signatures.match(Fx.proc(500, path: "/usr/local/bin/mcp-server-sqlite", argv: ["mcp-server-sqlite"]))?.id, "mcp-server-named")
    }

    func testUpstreamReportedShapes() {
        // Names listed in the upstream issues: Python and Node stdio servers launched by uvx and npx.
        XCTAssertEqual(Signatures.match(Fx.proc(500, path: "/Users/jane/.local/bin/chroma-mcp", argv: ["chroma-mcp", "--client-type", "persistent"]))?.id, "mcp-suffix")
        XCTAssertEqual(Signatures.match(node("/Users/jane/.npm/_npx/ab/node_modules/.bin/context7-mcp"))?.id, "mcp-suffix")
        XCTAssertEqual(Signatures.match(node("exec", "@upstash/context7-mcp@latest"))?.id, "mcp-suffix")
        XCTAssertEqual(Signatures.match(node("npm exec @modelcontextprotocol/server-memory"))?.id, "mcp-official")
    }

    /// npm rewrites its process title: the whole `npm exec <pkg>` string is argv[0], and the wrapper must still match.
    func testNpmExecWrapperWithRewrittenTitleMatches() {
        XCTAssertEqual(Signatures.match(Fx.proc(500, argv: ["npm exec @upstash/context7-mcp@latest"]))?.id, "mcp-suffix")
        XCTAssertEqual(Signatures.match(Fx.proc(500, argv: ["npm\texec\tmcp-server-time"]))?.id, "mcp-server-named")
        XCTAssertNil(Signatures.match(Fx.proc(500, argv: ["npm exec cowsay"])))
        // Not a launcher: its argv[0] is never split.
        XCTAssertNil(Signatures.match(Fx.proc(500, path: "/usr/bin/vim", argv: ["vim notes-mcp"])))
    }

    func testCliMcpServerAndOtherServerNamesMatch() {
        XCTAssertEqual(Signatures.match(Fx.proc(500, path: "/opt/homebrew/bin/uvx", argv: ["uvx", "cli-mcp-server"]))?.id, "mcp-server-named")
        XCTAssertEqual(Signatures.match(Fx.proc(500, path: "/Users/jane/.local/bin/cli-mcp-server", argv: ["cli-mcp-server"]))?.id, "mcp-server-named")
        XCTAssertEqual(Signatures.match(node("/x/bin/mcp-server.js"))?.id, "mcp-server-named")
        XCTAssertNil(Signatures.match(node("/x/bin/mcp-servers.js")))
    }

    func testCodexListenerNeedsStdio() {
        let ws = Fx.proc(500, path: "/usr/local/bin/codex", argv: ["codex", "app-server", "--listen", "ws://127.0.0.1:4500"])
        XCTAssertNotEqual(Signatures.match(ws)?.id, "codex-app-server")
        XCTAssertEqual(Signatures.match(ws)?.kind, .agentRoot, "a network listener is protected as a session")
        let inline = Fx.proc(500, path: "/usr/local/bin/codex", argv: ["codex", "app-server", "--listen=stdio://"])
        XCTAssertEqual(Signatures.match(inline)?.id, "codex-app-server")
    }

    /// Real launches carry 30+ flags before the marker; the cap must not cut them off (Scrub.argv is what the Mac layer applies).
    func testAutomationBrowsersWithRealisticFlagListsAreDetected() {
        let common = ["--disable-field-trial-config", "--disable-background-networking", "--disable-background-timer-throttling",
                      "--disable-backgrounding-occluded-windows", "--disable-back-forward-cache", "--disable-breakpad",
                      "--disable-client-side-phishing-detection", "--disable-component-extensions-with-background-pages",
                      "--disable-component-update", "--no-default-browser-check", "--disable-default-apps",
                      "--disable-dev-shm-usage", "--disable-extensions", "--disable-features=ImprovedCookieControls,LazyFrameLoading",
                      "--allow-pre-commit-input", "--disable-hang-monitor", "--disable-ipc-flooding-protection",
                      "--disable-popup-blocking", "--disable-prompt-on-repost", "--disable-renderer-backgrounding",
                      "--force-color-profile=srgb", "--metrics-recording-only", "--no-first-run", "--enable-automation",
                      "--password-store=basic", "--use-mock-keychain", "--no-service-autorun", "--export-tagged-pdf",
                      "--disable-search-engine-choice-screen", "--hide-scrollbars", "--mute-audio", "--no-sandbox"]
        let profile = "--user-data-dir=/var/folders/zz/T/playwright_chromiumdev_profile-AbCdEf"
        let playwright = Fx.proc(500, path: "/Users/jane/Library/Caches/ms-playwright/chromium-1140/chrome-mac/Chromium.app/Contents/MacOS/Chromium",
                                 argv: ["Chromium"] + common + ["--headless", profile, "--remote-debugging-pipe", "--no-startup-window"],
                                 cwd: "/", root: nil)
        let puppeteer = Fx.proc(501, path: "/Users/jane/.cache/puppeteer/chrome/mac_arm-126.0/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
                                argv: ["Google Chrome for Testing"] + common + [profile, "--headless=new", "--remote-debugging-port=0"],
                                cwd: "/", root: nil)
        for var p in [playwright, puppeteer] {
            XCTAssertGreaterThan(p.argv.count, 32)
            p.argv = Scrub.argv(p.argv)
            XCTAssertEqual(Signatures.match(p)?.id, "automation-chrome", p.name)
            XCTAssertEqual(Fx.tier(p), .ghost, p.name)
        }
    }

    func testAgentRootsReadOnlyTheCommandNotItsArguments() {
        // A leaked server whose arguments happen to name an agent is not a live session.
        for p in [node("server-filesystem", "/Users/jane/dev/claude", name: "npx"),
                  node("mcp-server-fetch", "--model", "codex", name: "uvx"),
                  node("-y", "mcp-server-x", "gemini", name: "npx"),
                  node("/x/server.js", "aider", "cursor-agent")] {
            XCTAssertNotEqual(Signatures.match(p)?.kind, .agentRoot, p.argv.joined(separator: " "))
        }
        XCTAssertEqual(Signatures.match(node("mcp-server-fetch", "--model", "codex", name: "uvx"))?.id, "mcp-server-named")
        // Real launches still count.
        XCTAssertEqual(Signatures.match(Fx.proc(500, path: "/usr/bin/python3", argv: ["python3", "-m", "aider"]))?.id, "aider-session")
        XCTAssertEqual(Signatures.match(node("-y", "@openai/codex", name: "npx"))?.id, "codex-session")
        XCTAssertEqual(Signatures.match(node("/x/claude.js"))?.id, "claude-session")
        XCTAssertEqual(Signatures.match(Fx.proc(500, path: "/bin/sh", argv: ["sh", "-c", "claude --resume"]))?.id, "claude-session")
        XCTAssertEqual(Matching.commandHead(["npx", "-y", "pkg", "x"]), ["npx", "pkg"])
        XCTAssertEqual(Matching.commandHead(["node"]), ["node"])
    }

    func testDefaultPlaywrightMcpChromeIsDetectedButTheUsersChromeIsNot() {
        let path = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        // VERIFY the real argv on a dump: @playwright/mcp launches the installed Chrome with its own profile under ms-playwright.
        let mcp = chrome("--user-data-dir=/Users/jane/Library/Caches/ms-playwright/mcp-chrome-ab12cd", "--remote-debugging-pipe", path: path)
        let tmp = chrome("--user-data-dir=/var/folders/zz/T/playwright_chromiumdev_profile-AbCdEf", "--remote-debugging-pipe", path: path)
        for var p in [mcp, tmp] {
            p.argv = Scrub.argv(p.argv)
            XCTAssertEqual(Signatures.match(p)?.id, "automation-chrome", p.argv.joined(separator: " "))
            XCTAssertEqual(Fx.tier(p), .ghost)
        }
        // Near misses: the user's Chrome, a profile marker without the pipe, and a helper process inside the bundle.
        XCTAssertNil(Signatures.match(chrome("--remote-debugging-pipe", path: path)))
        XCTAssertNil(Signatures.match(chrome("--user-data-dir=/Users/jane/Library/Caches/ms-playwright/mcp-chrome-ab12cd", path: path)))
        let helper = chrome("--user-data-dir=/Users/jane/Library/Caches/ms-playwright/mcp-chrome-ab12cd", "--remote-debugging-pipe",
                            path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper")
        XCTAssertNil(Signatures.match(helper))
    }

    func testMatchingBase() {
        XCTAssertEqual(Matching.base("/a/b/mcp-server-x.js"), "mcp-server-x")
        XCTAssertEqual(Matching.base("/a/b/server.mjs"), "server")
        XCTAssertEqual(Matching.base("/a/b/x.cjs"), "x")
        XCTAssertEqual(Matching.base("/a/b/x.ts"), "x")
        XCTAssertEqual(Matching.base("mcp_server_git.py"), "mcp_server_git")
        XCTAssertEqual(Matching.base(".js"), ".js")
        XCTAssertEqual(Matching.base("mcp-remote@1.2.3"), "mcp-remote")
        XCTAssertEqual(Matching.base("@upstash/context7-mcp@latest"), "context7-mcp")
        XCTAssertEqual(Matching.base("mcp-server-time /Users/jane/dir"), "mcp-server-time")
        XCTAssertEqual(Matching.base(""), "")
    }

    func testLauncherArgumentsAfterTheScriptDoNotNameAServer() {
        // The user's own job: the script is `build.js`; the server-looking words are its arguments.
        XCTAssertNil(Signatures.match(node("/Users/jane/dev/foo/build.js", "mcp-server-x")))
        XCTAssertNil(Signatures.match(node("/Users/jane/dev/foo/run.py", "--target", "docs-mcp")))
        XCTAssertNil(Signatures.match(node("/Users/jane/dev/foo/run.TS", "mcp-server-x")))
        // The script itself, a bin shim and a launcher without a script still match.
        XCTAssertEqual(Signatures.match(node("/x/mcp-server-x.js", "--stdio"))?.id, "mcp-server-named")
        XCTAssertEqual(Signatures.match(node("/x/.bin/mcp-server-x", "/dir"))?.id, "mcp-server-named")
        XCTAssertEqual(Signatures.match(node("-y", "context7-mcp", name: "npx"))?.id, "mcp-suffix")
        // Package names and flags still see the whole argv.
        XCTAssertEqual(Signatures.match(node("/x/cli.js", "@playwright/mcp@latest"))?.id, "playwright-mcp")
        XCTAssertEqual(Matching.scriptHead(["node", "a.js", "b.js", "c"]), ["node", "a.js"])
        XCTAssertEqual(Matching.scriptHead(["a.js"]), ["a.js"], "argv[0] is the program, never the script")
    }

    func testFlagPatternAcceptsEqualsFormOnly() {
        let p = Fx.proc(500, argv: ["chrome", "--headless=new", "--headlessx", "--remote-debugging-pipe"])
        XCTAssertTrue(Matching.matches(.flag("--headless"), p))
        XCTAssertTrue(Matching.matches(.flag("--remote-debugging-pipe"), p))
        XCTAssertFalse(Matching.matches(.flag("--headles"), p))
        XCTAssertFalse(Matching.matches(.all([]), p), "an empty all never matches")
    }

    func testEnvMarkers() {
        XCTAssertEqual(EnvMarkers.allowed, ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"])
        XCTAssertEqual(EnvMarkers.agent(for: "CLAUDECODE"), .claudeCode)
        XCTAssertNil(EnvMarkers.agent(for: "HOME"))
    }
}
