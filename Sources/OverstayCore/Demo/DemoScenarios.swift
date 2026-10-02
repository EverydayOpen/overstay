import Foundation

/// Synthetic process tables for demo mode (BUILD_PLAN §9). Pure and deterministic: one scenario and one `now` always give
/// the same table, so screenshots do not drift. Home is the example user jane. The table is plain input for the real `Scan.analyze`,
/// `StopPlanner` and `Classifier`; nothing here decides what is a Ghost, so the demo exercises the real logic.
public enum DemoScenarios {
    public static let home = "/Users/jane"
    public static let selfPid: Int32 = 4_200
    static let uid: UInt32 = 501
    static let tty: UInt32 = 16_777_233

    /// The table a scenario starts from. `refused` and `survivors` start like `leftovers`; they differ in `answer`.
    public static func rawScan(_ scenario: DemoScenario, now: Date) -> RawScan {
        var t = Table(now: Int64(now.timeIntervalSince1970))
        t.desktop()
        var unreadable = 0
        switch scenario {
        case .quiet, .firstRun:
            break
        case .leftovers, .refused, .survivors:
            t.ghosts()
            t.maybes(Array(Maybe.allCases.prefix(4)))
            unreadable = 3
        case .maybeOnly:
            t.maybes(Maybe.allCases)
            unreadable = 3
        }
        return RawScan(processes: t.rows, selfPid: selfPid, uid: uid, home: home, scannedAt: now, unreadableCount: unreadable)
    }

    /// What the fake signaller answers for one target. `refused` is EPERM for the Codex helpers of `bar`; `survivors`
    /// ignores the polite signal for the headless browsers and every eleventh pid, and a force plan finishes them.
    public static func answer(_ scenario: DemoScenario, for target: StopTarget, mode: StopMode) -> TargetStatus {
        let done: TargetStatus = mode == .force ? .forceStopped : .stopped
        switch scenario {
        case .refused where target.agent == .codex && target.projectName == "bar":
            return .refused
        case .survivors where mode == .terminate && (target.agent == .automationBrowser || target.identity.pid % 11 == 0):
            return .survived
        default:
            return done
        }
    }

    /// Earlier stops, so the activity screen has days to group. Oldest first. Empty where nothing has ever run.
    public static func history(for scenario: DemoScenario, now: Date) -> [ActivityEntry] {
        if scenario == .quiet || scenario == .firstRun { return [] }
        let rows: [(ago: Double, batch: String, pid: Int32, name: String, sig: String, agent: AgentKind, project: String?, mb: UInt64, why: String)] = [
            (260_000, "history-2", 17_311, "codex", "codex-app-server", .codex, "api", 58,
             "Parent is gone. Looks like a Codex helper. No live session in api."),
            (260_000, "history-2", 17_318, "node_repl", "codex-node-repl", .codex, "api", 91,
             "Parent is gone. Looks like a Codex helper. No live session in api."),
            (90_000, "history-1", 18_190, "npm", "mcp-official", .unattributed, "web", 41,
             "Parent is gone. Looks like an MCP server. No live session in web."),
            (90_000, "history-1", 18_199, "zsh", "mcp-server-named", .unattributed, "web", 6,
             "Parent is gone. Looks like an MCP server. No live session in web."),
            (90_000, "history-1", 18_204, "node", "mcp-official", .unattributed, "web", 74,
             "Parent is gone. Looks like an MCP server. No live session in web."),
            (90_000, "history-1", 18_230, "Google Chrome for Testing", "automation-chrome", .automationBrowser, nil, 512,
             "Parent is gone. Looks like an automation browser. No live session found."),
        ]
        return rows.map {
            ActivityEntry(timestamp: now.addingTimeInterval(-$0.ago), batchID: $0.batch, mode: .terminate, pid: $0.pid,
                          executable: $0.name, signatureID: $0.sig, agent: $0.agent, project: $0.project,
                          footprintBytes: $0.mb << 20, result: .stopped, why: $0.why)
        }
    }

    /// Splits `total` MB over `weights` exactly (the first gets the remainder), so a group adds up to its stated size.
    static func split(_ total: Int, _ weights: [Int]) -> [Int] {
        guard !weights.isEmpty else { return [] }
        let sum = max(weights.reduce(0, +), 1)
        var out = weights.map { total * $0 / sum }
        out[0] += total - out.reduce(0, +)
        return out
    }

    // MARK: - The tables

    private enum Maybe: CaseIterable {
        /// Listens on the network: probably started on purpose.
        case sseServer
        /// Under the age gate.
        case youngCodex
        /// A generic dev server.
        case viteDev
        /// Something still holds the other end of its input pipe.
        case pipeHeld
        /// A live Claude Code session works in the same project.
        case liveSession
        case nextDev
    }

    private static let packages: [(npm: String, bin: String)] = [
        ("@modelcontextprotocol/server-filesystem", "mcp-server-filesystem"),
        ("@playwright/mcp@latest", "playwright-mcp"),
        ("chrome-devtools-mcp@latest", "chrome-devtools-mcp"),
        ("@upstash/context7-mcp", "context7-mcp"),
        ("@modelcontextprotocol/server-github", "mcp-server-github"),
        ("@modelcontextprotocol/server-memory", "mcp-server-memory"),
    ]

    private struct Table {
        let now: Int64
        var rows: [ProcessSnapshot] = []
        private var next: Int32 = 20_000
        private var weights: [Int] = []
        private var first = 0

        init(now: Int64) { self.now = now }

        @discardableResult
        mutating func add(_ path: String, _ argv: [String], ppid: Int32 = 1, cwd: String? = nil, root: String? = nil, age: Int,
                          weight: Int = 1, mb: Int = 0, uid: UInt32 = DemoScenarios.uid, pid: Int32? = nil, name: String? = nil,
                          tty: UInt32? = nil, sid: Int32? = nil, stdin: StdinState = .unknown) -> Int32 {
            let id = pid ?? next
            if pid == nil { next += 1 + next % 4 }
            rows.append(ProcessSnapshot(pid: id, ppid: ppid, pgid: id, sid: sid, uid: uid, startSeconds: now - Int64(age),
                                        path: path, name: name, argv: argv, cwd: cwd, projectRoot: root, footprintBytes: UInt64(mb) << 20,
                                        ttyDevice: tty, isSessionLeader: sid == id, stdin: stdin))
            weights.append(weight)
            return id
        }

        mutating func begin() {
            first = rows.count
            weights = []
        }

        /// Gives the rows added since `begin` exactly `mb` megabytes between them, in proportion to their weights.
        mutating func end(mb: Int) {
            for (i, m) in DemoScenarios.split(mb, weights).enumerated() { rows[first + i].footprintBytes = UInt64(m) << 20 }
        }

        /// The user's session and everything around it: a terminal, a shell, one live Claude Code session in ~/dev/api,
        /// this app, system agents and ordinary apps. None of it is ever listed.
        mutating func desktop() {
            add("/sbin/launchd", [], ppid: 0, age: 400_000, uid: 0, pid: 1)
            let terminal = add("/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", ["Terminal"], age: 300_000, mb: 180, pid: 612)
            let api = "\(DemoScenarios.home)/dev/api"
            let shell = add("/opt/homebrew/bin/zsh", ["-zsh"], ppid: terminal, cwd: api, age: 29_000, mb: 9, pid: 3_010,
                            tty: DemoScenarios.tty, sid: 3_010)
            add("\(DemoScenarios.home)/.local/share/claude/versions/2.1.0", ["claude"], ppid: shell, cwd: api, root: api,
                age: 7_200, mb: 410, pid: 3_050, name: "claude", tty: DemoScenarios.tty, sid: shell)
            add("/Applications/Overstay.app/Contents/MacOS/Overstay", ["Overstay"], cwd: "/", age: 30, mb: 96, pid: DemoScenarios.selfPid)
            for (i, name) in ["cfprefsd", "distnoted", "UserEventAgent", "usernoted", "lsd"].enumerated() {
                add("/usr/libexec/\(name)", [name], age: 300_000, mb: 6 + i * 5)
            }
            let agents = ["xpcproxy", "cfprefsd", "mdworker_shared", "trustd", "secd", "nsurlsessiond", "photoanalysisd", "akd", "bluetoothd",
                          "coreaudiod", "sharingd", "routined", "searchpartyuserd", "knowledgeconstructiond", "ControlCenter"]
            for i in 0..<240 {   // the long tail of a real process table, so "Checked N processes" reads like one
                let name = agents[i % agents.count]
                add("/usr/libexec/\(name)", [name], age: 250_000 - i * 400, mb: 4 + i % 23)
            }
            let apps = ["Safari", "Mail", "Slack", "Xcode", "Notes", "Music", "Preview", "Messages", "Figma", "Spotify", "Calendar", "Finder"]
            for (i, app) in apps.enumerated() {
                let dir = app == "Finder" ? "/System/Library/CoreServices/Finder.app" : "/Applications/\(app).app"
                let main = add("\(dir)/Contents/MacOS/\(app)", [app], age: 120_000 + i * 9_000, mb: 150 + i * 37)
                for h in ["Renderer", "GPU", "Network"].prefix(1 + i % 3) {
                    add("\(dir)/Contents/Frameworks/\(app) Helper (\(h)).app/Contents/MacOS/\(app) Helper (\(h))",
                        ["\(app) Helper (\(h))"], ppid: main, age: 119_000 + i * 9_000, mb: 40 + i * 11)
                }
            }
        }

        /// Seconds since start of tree `j`; tree 0 is the oldest, so it sets "started 3 days ago".
        func treeAge(_ j: Int, _ oldest: Int) -> Int { j == 0 ? oldest : oldest - (j * 7_919) % (oldest / 5) }

        mutating func ghosts() {
            mcpGroup("foo", sizes: Array(repeating: 3, count: 20) + [1], mb: 3_174, oldest: 273_600)
            codexGroup("bar", sizes: Array(repeating: 5, count: 8), mb: 2_253, oldest: 183_600)
            browserGroup(sizes: [6, 6], mb: 1_434, oldest: 19_200)
            mcpGroup("baz", sizes: Array(repeating: 3, count: 12) + [2], mb: 1_536, oldest: 349_200)
            codexGroup("qux", sizes: Array(repeating: 4, count: 8), mb: 1_229, oldest: 108_000)
        }

        /// Trees of `npm exec` > zsh > node (shorter for sizes 2 and 1): MCP servers whose agent has gone.
        mutating func mcpGroup(_ project: String, sizes: [Int], mb: Int, oldest: Int) {
            let dir = "\(DemoScenarios.home)/dev/\(project)"
            begin()
            for (j, size) in sizes.enumerated() {
                let pkg = DemoScenarios.packages[j % DemoScenarios.packages.count]
                let age = treeAge(j, oldest)
                var parent: Int32 = 1
                if size >= 2 { parent = add("/opt/homebrew/bin/npm", ["npm exec \(pkg.npm) \(dir)"], cwd: dir, root: dir, age: age) }
                if size >= 3 { parent = add("/opt/homebrew/bin/zsh", ["zsh", "-c", "\(pkg.bin) \(dir)"], ppid: parent, cwd: dir, root: dir, age: age - 3) }
                let bin = "\(DemoScenarios.home)/.npm/_npx/\(String(0x9c1e00 + j * 977, radix: 16))/node_modules/.bin/\(pkg.bin)"
                add("/opt/homebrew/bin/node", ["node", bin, dir], ppid: parent, cwd: dir, root: dir, age: age - 6, weight: 6 + j * 5 % 4)
            }
            end(mb: mb)
        }

        /// Trees of one `codex app-server` with node_repl helpers under it.
        mutating func codexGroup(_ project: String, sizes: [Int], mb: Int, oldest: Int) {
            let dir = "\(DemoScenarios.home)/dev/\(project)"
            begin()
            for (j, size) in sizes.enumerated() {
                let age = treeAge(j, oldest)
                let server = add("/opt/homebrew/bin/codex", ["codex", "app-server", "--listen", "stdio://"], cwd: dir, root: dir, age: age, weight: 3)
                for k in 1..<size {
                    add("\(DemoScenarios.home)/.codex/bin/node_repl", ["node_repl"], ppid: server, cwd: dir, root: dir,
                        age: age - 5 * k, weight: 2 + (j + k) % 3)
                }
            }
            end(mb: mb)
        }

        /// Trees of one headless Chrome for Testing with helpers. Browsers started by a tool have no project folder.
        mutating func browserGroup(sizes: [Int], mb: Int, oldest: Int) {
            let app = "\(DemoScenarios.home)/.cache/puppeteer/chrome/mac_arm-131.0.6778.204/chrome-mac-arm64/Google Chrome for Testing.app"
            let kinds = [("Renderer", "renderer"), ("GPU", "gpu-process"), ("Renderer", "renderer"), ("Renderer", "renderer"), ("Plugin", "utility")]
            begin()
            for (j, size) in sizes.enumerated() {
                let age = treeAge(j, oldest)
                let main = add("\(app)/Contents/MacOS/Google Chrome for Testing",
                               ["\(app)/Contents/MacOS/Google Chrome for Testing", "--headless=new", "--remote-debugging-pipe",
                                "--user-data-dir=/var/folders/zz/T/puppeteer_dev_chrome_profile-\(j)", "--no-first-run"],
                               cwd: "/", age: age, weight: 30)
                for k in 1..<size {
                    let (title, type) = kinds[(k - 1) % kinds.count]
                    let name = "Google Chrome for Testing Helper (\(title))"
                    let path = "\(app)/Contents/Frameworks/Google Chrome for Testing Framework.framework/Versions/131.0.6778.204/Helpers/\(name).app/Contents/MacOS/\(name)"
                    add(path, [path, "--type=\(type)", "--headless"], ppid: main, cwd: "/", age: age - 4 * k, weight: 2 + k % 2)
                }
            }
            end(mb: mb)
        }

        mutating func maybes(_ which: [Maybe]) {
            let dev = "\(DemoScenarios.home)/dev"
            let node = "/opt/homebrew/bin/node"
            let npx = "\(DemoScenarios.home)/.npm/_npx"
            for m in which {
                switch m {
                case .sseServer:
                    add(node, ["node", "\(npx)/9c1e/node_modules/.bin/mcp-server-everything", "--transport", "sse", "--port", "3845"],
                        cwd: "\(dev)/foo", root: "\(dev)/foo", age: 172_800, mb: 88)
                case .youngCodex:
                    add("/opt/homebrew/bin/codex", ["codex", "app-server", "--listen", "stdio://"], cwd: "\(dev)/bar", root: "\(dev)/bar", age: 240, mb: 61)
                case .viteDev:
                    add(node, ["node", "\(dev)/baz/node_modules/.bin/vite"], cwd: "\(dev)/baz", root: "\(dev)/baz", age: 190_000, mb: 140)
                case .pipeHeld:
                    add("/opt/homebrew/bin/codex", ["codex", "app-server", "--listen", "stdio://"], cwd: "\(dev)/qux", root: "\(dev)/qux",
                        age: 86_400, mb: 72, stdin: .writerAlive)
                case .liveSession:
                    add(node, ["node", "\(npx)/4d2f/node_modules/.bin/mcp-server-memory", "\(dev)/api"], cwd: "\(dev)/api", root: "\(dev)/api",
                        age: 10_800, mb: 54)
                case .nextDev:
                    add(node, ["next-server (v14.2.3)"], cwd: "\(dev)/web", root: "\(dev)/web", age: 18_000, mb: 310)
                }
            }
        }
    }
}
