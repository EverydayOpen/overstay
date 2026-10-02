import Foundation

/// The hard-coded protected list (BUILD_PLAN §3 rule 5). A protected process classifies as `.protected` and can never
/// be selected, planned or signalled. The user's `neverTouch` list adds to it and never subtracts.
public enum Protected {
    private static let named: [String: String] = {
        var d: [String: String] = [:]
        func add(_ reason: String, _ names: [String]) { for n in names { d[n] = reason } }
        add("a core macOS process", ["launchd", "kernel_task", "WindowServer", "loginwindow", "Finder", "Dock"])
        add("a terminal app", ["Terminal", "iTerm", "iTerm2", "Ghostty", "ghostty", "WezTerm", "wezterm", "wezterm-gui",
                               "kitty", "Alacritty", "alacritty"])
        add("a terminal multiplexer", ["tmux", "screen", "zellij"])
        add("an ssh or gpg agent", ["ssh", "sshd", "ssh-agent", "ssh-add", "gpg-agent", "gpg", "gpg-connect-agent"])
        add("a container or VM helper", ["Docker", "docker", "colima", "lima", "limactl", "orbstack", "OrbStack", "vfkit",
                                         "virtiofsd", "qemu-img"])
        add("a database", ["postgres", "mysqld", "mariadbd", "mongod", "redis-server", "valkey-server", "sqlite3"])
        add("a language server", ["sourcekit-lsp", "clangd", "gopls", "rust-analyzer", "pyright", "pyright-langserver",
                                  "tsserver", "jdtls", "lua-language-server", "solargraph"])
        return d
    }()

    /// Exact executable basenames.
    public static let names: Set<String> = Set(named.keys)
    private static let namePrefixes: [(String, String)] = [("qemu", "a container or VM helper"),
                                                           ("com.docker", "a container or VM helper"),
                                                           ("com.apple.", "a core macOS process")]
    private static let languageServerSuffixes = ["-language-server", "-languageserver", "-langserver"]
    public static let pathPrefixes: [String] = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"]

    /// nil = not protected. Rules in §3 rule 5, plus: self, ancestors, pid <= 1, another user.
    public static func reason(for p: ProcessSnapshot, in world: World, prefs: Preferences) -> String? {
        if p.pid <= 1 { return "a core macOS process" }
        if p.pid == world.selfPid { return "Overstay itself" }
        if world.ancestors.contains(p.pid) { return "it hosts this app (terminal, shell or editor)" }
        if p.uid != world.uid { return "it belongs to another user" }
        if pathPrefixes.contains(where: { p.path.hasPrefix($0) }) { return "system software" }
        let sig = Signatures.match(p)
        if let r = byName(p) { return r }
        if p.path.contains(".app/"), sig?.kind != .automationBrowser, !p.path.contains("/Python.app/Contents/MacOS/") {
            return "inside an app bundle"
        }
        if p.ttyDevice != nil, let sid = p.sid, world.isSessionLeaderAlive(sid) { return "its terminal session is alive" }
        if neverTouch(p, prefs) { return "on your never-touch list" }
        if sig?.kind == .agentRoot { return "an agent session" }
        return nil
    }

    private static func byName(_ p: ProcessSnapshot) -> String? {
        for n in [p.name, PathText.basename(p.path)] where !n.isEmpty {
            if let r = named[n] { return r }
            if let (_, r) = namePrefixes.first(where: { n.hasPrefix($0.0) }) { return r }
            if languageServerSuffixes.contains(where: { n.hasSuffix($0) }) { return "a language server" }
        }
        // `node …/tsserver.js`, `node …/foo-language-server`: language servers run under a launcher.
        if Matching.isLauncher(p), p.argv.contains(where: {
            let b = Matching.base($0)
            return b == "tsserver" || languageServerSuffixes.contains(where: b.hasSuffix)
        }) { return "a language server" }
        return nil
    }

    private static func neverTouch(_ p: ProcessSnapshot, _ prefs: Preferences) -> Bool {
        prefs.neverTouch.contains { raw in
            var e = raw.trimmingCharacters(in: .whitespaces)
            if e.count > 1, e.hasSuffix("/") { e.removeLast() }
            if e.isEmpty { return false }
            if e.hasPrefix("/") {
                e = PathText.systemResolved(e)
                let cwd = p.cwd.map(PathText.systemResolved)
                return p.projectRoot.map(PathText.systemResolved) == e || cwd == e || (cwd?.hasPrefix(e + "/") ?? false)
            }
            return p.name == e || PathText.basename(p.path) == e
        }
    }
}
