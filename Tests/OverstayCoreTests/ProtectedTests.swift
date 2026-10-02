import Foundation
import XCTest
@testable import OverstayCore

final class ProtectedTests: XCTestCase {
    private func reason(_ p: ProcessSnapshot, with extra: [ProcessSnapshot] = [], prefs: Preferences = .default) -> String? {
        Protected.reason(for: p, in: Fx.world([p] + extra), prefs: prefs)
    }

    func testPidOneAndBelowAreAlwaysProtected() {
        XCTAssertNotNil(reason(Fx.proc(1, ppid: 0, path: "/sbin/launchd")))
        XCTAssertNotNil(reason(Fx.proc(0, ppid: 0, path: "/kernel")))
        XCTAssertNotNil(reason(Fx.proc(-1, ppid: 0, path: "/x")))
    }

    func testSelfAndEveryAncestorAreProtected() {
        let w = Fx.world([])
        XCTAssertEqual(w.ancestors, [800, 850])
        for pid in [Fx.selfPid, 850, 800] {
            XCTAssertNotNil(Protected.reason(for: w.byPid[pid]!, in: w, prefs: .default), "pid \(pid)")
        }
        // Even an ancestor that looks exactly like a leftover tool server is never offered.
        let host = Fx.mcp(700)
        var table = Fx.base()
        table[3].ppid = 700
        let w2 = World(RawScan(processes: table + [host], selfPid: Fx.selfPid, uid: Fx.uid, home: Fx.home, scannedAt: Fx.now))
        XCTAssertTrue(w2.ancestors.contains(700))
        XCTAssertEqual(Classifier.classify(host, in: w2, prefs: .default, now: Fx.now).tier, .protected)
    }

    func testAncestorChainIsLoopSafe() {
        let a = Fx.proc(10, ppid: 11), b = Fx.proc(11, ppid: 10)
        let me = Fx.proc(Fx.selfPid, ppid: 10)
        let w = World(RawScan(processes: [a, b, me], selfPid: Fx.selfPid, uid: Fx.uid, home: Fx.home, scannedAt: Fx.now))
        XCTAssertEqual(w.ancestors, [10, 11])
    }

    func testAnotherUsersProcessIsProtected() {
        XCTAssertNotNil(reason(Fx.mcp(500).with(uid: 502)))
    }

    func testSystemPathsAndBundles() {
        for path in ["/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock", "/usr/libexec/trustd", "/usr/sbin/cfprefsd",
                     "/sbin/launchd", "/Library/Apple/System/Library/x", "/Applications/Slack.app/Contents/MacOS/Slack"] {
            XCTAssertNotNil(reason(Fx.proc(500, path: path, argv: ["x"])), path)
        }
        XCTAssertEqual(reason(Fx.proc(500, path: "/Applications/Slack.app/Contents/MacOS/Slack", argv: ["x"])), "inside an app bundle")
    }

    func testNamedProgramsAreProtected() {
        let names = ["Terminal", "iTerm2", "Ghostty", "WezTerm", "kitty", "Alacritty", "tmux", "screen", "zellij", "ssh", "sshd",
                     "ssh-agent", "gpg-agent", "docker", "colima", "limactl", "OrbStack", "qemu-system-aarch64", "postgres",
                     "mysqld", "mongod", "redis-server", "sourcekit-lsp", "clangd", "gopls", "rust-analyzer", "pyright",
                     "typescript-language-server", "vscode-json-languageserver", "Finder", "Dock", "WindowServer", "loginwindow",
                     "com.docker.backend"]
        for n in names { XCTAssertNotNil(reason(Fx.proc(500, path: "/opt/homebrew/bin/\(n)", argv: [n])), n) }
        XCTAssertEqual(Protected.names.isSuperset(of: ["launchd", "kernel_task", "WindowServer", "loginwindow", "Finder", "Dock"]), true)
    }

    func testLanguageServersRunningUnderNodeAreProtected() {
        let ts = Fx.proc(500, argv: ["node", "/x/node_modules/typescript/lib/tsserver.js", "--stdio"])
        XCTAssertEqual(reason(ts), "a language server")
        let ls = Fx.proc(501, argv: ["node", "/x/node_modules/.bin/vscode-eslint-language-server", "--stdio"])
        XCTAssertEqual(reason(ls), "a language server")
        XCTAssertNil(reason(Fx.mcp(502)))
    }

    func testAnAutomationBrowserInsideABundleIsTheOnlyBundleException() {
        let pw = Fx.proc(500, path: "/Users/jane/Library/Caches/ms-playwright/chromium-1/chrome-mac/Chromium.app/Contents/MacOS/Chromium",
                         argv: ["Chromium", "--remote-debugging-pipe"], cwd: "/", root: nil)
        XCTAssertNil(reason(pw))
        let python = Fx.proc(501, path: "/opt/homebrew/Cellar/python@3.12/3.12.4/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python",
                             argv: ["python", "-m", "mcp_server_git"])
        XCTAssertNil(reason(python), "Homebrew Python runs inside an app bundle")
    }

    func testTerminalSessionRule() {
        // Controlling tty + live session leader: protected. Leader gone: not protected.
        XCTAssertEqual(reason(Fx.mcp(500).with(tty: 1, sid: 850)), "its terminal session is alive")
        XCTAssertNil(reason(Fx.mcp(500).with(tty: 1, sid: 4242)))
        XCTAssertNil(reason(Fx.mcp(500).with(tty: nil, sid: 850)), "no controlling tty")
        // A pid that is not a session leader does not count as one (pid reuse).
        let impostor = Fx.proc(4242, ppid: 850, argv: ["x"], sid: 777)
        XCTAssertNil(reason(Fx.mcp(500).with(tty: 1, sid: 4242), with: [impostor]))
    }

    func testNeverTouchAddsByNameAndByProjectButNeverSubtracts() {
        let p = Fx.mcp(500)
        XCTAssertNil(reason(p))
        XCTAssertEqual(reason(p, prefs: Preferences(neverTouch: ["node"])), "on your never-touch list")
        XCTAssertNotNil(reason(p, prefs: Preferences(neverTouch: ["/Users/jane/dev/foo"])))
        XCTAssertNotNil(reason(p, prefs: Preferences(neverTouch: ["/Users/jane/dev/foo/"])))
        XCTAssertNotNil(reason(p, prefs: Preferences(neverTouch: ["/Users/jane/dev"])), "a folder protects everything below it")
        XCTAssertNil(reason(p, prefs: Preferences(neverTouch: ["/Users/jane/dev/bar", "python", ""])))
        // The kernel reports real paths: an entry typed through /tmp, /var or /etc must still match.
        let tmp = Fx.mcp(501, cwd: "/private/tmp/x/sub", root: "/private/tmp/x")
        XCTAssertNotNil(reason(tmp, prefs: Preferences(neverTouch: ["/tmp/x"])))
        XCTAssertNotNil(reason(tmp, prefs: Preferences(neverTouch: ["/tmp/x/"])))
        XCTAssertNotNil(reason(tmp, prefs: Preferences(neverTouch: ["/private/tmp/x"])))
        XCTAssertNotNil(reason(Fx.mcp(502, cwd: "/private/var/db/w", root: nil), prefs: Preferences(neverTouch: ["/var/db"])))
        XCTAssertNil(reason(tmp, prefs: Preferences(neverTouch: ["/tmp/xy", "/tmpx"])))
        XCTAssertEqual(PathText.systemResolved("/tmpfoo"), "/tmpfoo")
        // Removing built-ins is impossible: an empty list leaves Finder protected.
        XCTAssertNotNil(reason(Fx.proc(501, path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", argv: ["Finder"]),
                               prefs: Preferences(neverTouch: [])))
    }
}

extension ProcessSnapshot {
    func with(uid: UInt32? = nil, tty: UInt32?? = nil, sid: Int32?? = nil) -> ProcessSnapshot {
        var c = self
        if let uid { c.uid = uid }
        if let tty { c.ttyDevice = tty }
        if let sid { c.sid = sid }
        return c
    }
}
