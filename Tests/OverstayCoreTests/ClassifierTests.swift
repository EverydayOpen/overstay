import Foundation
import XCTest
@testable import OverstayCore

final class ClassifierTests: XCTestCase {
    func testOrphanedToolServerWithNoSessionIsAGhost() {
        let c = Fx.classify(Fx.mcp(500))
        XCTAssertEqual(c.tier, .ghost)
        XCTAssertEqual(c.evidence.signatureID, "mcp-server-named")
        XCTAssertTrue(c.evidence.orphaned)
        XCTAssertEqual(c.agent, .unattributed)
        XCTAssertEqual(c.why, "Parent is gone. Looks like an MCP server. No live session in foo.")
    }

    func testAServerWithALiveParentBelongsToThatParent() {
        let parent = Fx.proc(600, argv: ["tool"], cwd: "/Users/jane/dev/foo")
        XCTAssertEqual(Fx.tier(Fx.mcp(500, ppid: 600), with: [parent]), .ignored)
    }

    func testAgeGateBoundary() {
        XCTAssertEqual(Fx.tier(Fx.mcp(500, age: 599)), .maybe)
        XCTAssertEqual(Fx.tier(Fx.mcp(500, age: 600)), .ghost)
        let gated = Fx.classify(Fx.mcp(500, age: 599))
        XCTAssertFalse(gated.evidence.ageGateMet)
        XCTAssertEqual(gated.why, "Parent is gone. Looks like an MCP server. Started 9 min ago, under the 10 min age gate.")
        XCTAssertEqual(Fx.tier(Fx.mcp(500, age: 1799), prefs: Preferences(ageGateMinutes: 30)), .maybe)
        XCTAssertEqual(Fx.tier(Fx.mcp(500, age: 1800), prefs: Preferences(ageGateMinutes: 30)), .ghost)
    }

    func testALiveSessionInTheSameProjectMakesItAMaybe() {
        let c = Fx.classify(Fx.mcp(500), with: [Fx.claude(400)])
        XCTAssertEqual(c.tier, .maybe)
        XCTAssertEqual(c.evidence.liveSessionPids, [400])
        XCTAssertEqual(c.why, "Parent is gone. Looks like an MCP server. A live session is using foo, so it may still be needed.")
    }

    func testASessionElsewhereDoesNotCount() {
        let other = Fx.claude(400, cwd: "/Users/jane/dev/bar", root: "/Users/jane/dev/bar")
        XCTAssertEqual(Fx.tier(Fx.mcp(500), with: [other]), .ghost)
    }

    func testSessionsWithoutProjectRootsMatchOnWorkingFolderOnly() {
        let p = Fx.mcp(500, cwd: "/Users/jane/scratch", root: nil)
        XCTAssertEqual(Fx.tier(p, with: [Fx.claude(400, cwd: "/Users/jane/scratch", root: nil)]), .maybe)
        XCTAssertEqual(Fx.tier(p, with: [Fx.claude(400, cwd: "/Users/jane/other", root: nil)]), .ghost)
        // An IDE or session whose workspace is unknown ("/" or nothing) never makes everything live.
        XCTAssertEqual(Fx.tier(Fx.mcp(500, cwd: "/", root: nil), with: [Fx.claude(400, cwd: "/", root: nil)]), .maybe)
        XCTAssertEqual(Fx.tier(p, with: [Fx.claude(400, cwd: nil, root: nil)]), .ghost)
    }

    func testUnknownProjectFailsClosedToMaybe() {
        let c = Fx.classify(Fx.mcp(500, cwd: nil, root: nil))
        XCTAssertEqual(c.tier, .maybe)
        XCTAssertTrue(c.why.contains("project could not be determined"))
        // cwd "/" names no project either, so live sessions could never demote it: same fail-closed answer.
        let root = Fx.classify(Fx.mcp(500, cwd: "/", root: nil))
        XCTAssertEqual(root.tier, .maybe)
        XCTAssertTrue(root.evidence.projectUnknown)
        // cwd == home is a real folder that live sessions can match.
        XCTAssertEqual(Fx.tier(Fx.mcp(500, cwd: Fx.home, root: nil)), .ghost)
        XCTAssertEqual(Fx.tier(Fx.mcp(500, cwd: Fx.home, root: nil), with: [Fx.claude(400, cwd: Fx.home, root: nil)]), .maybe)
        // Automation browsers have no project by nature: a known cwd is enough, an unreadable one still fails closed.
        func browser(_ cwd: String?) -> ProcessSnapshot {
            Fx.proc(520, path: "/x/ms-playwright/chromium-1/Chromium.app/Contents/MacOS/Chromium",
                    argv: ["Chromium", "--remote-debugging-pipe"], cwd: cwd, root: nil)
        }
        XCTAssertEqual(Fx.tier(browser("/")), .ghost)
        XCTAssertEqual(Fx.tier(browser(nil)), .maybe)
    }

    func testDeliberateNetworkServersNeverGoAboveMaybe() {
        func server(_ args: [String]) -> ProcessSnapshot {
            Fx.proc(500, argv: ["node", "/Users/jane/.npm/_npx/ab/node_modules/.bin/mcp-server-x"] + args)
        }
        XCTAssertEqual(Fx.tier(server(["--stdio"])), .ghost)
        XCTAssertEqual(Fx.tier(server(["--transport", "stdio"])), .ghost)
        XCTAssertEqual(Fx.tier(server(["--transport=stdio"])), .ghost)
        for args in [["--port", "8080"], ["--port=8080"], ["--host", "0.0.0.0"], ["--sse"], ["--transport", "sse"],
                     ["--transport=streamable-http"], ["--listen", "ws://127.0.0.1:4500"], ["--listen=http://127.0.0.1:3000"]] {
            let c = Fx.classify(server(args))
            XCTAssertEqual(c.tier, .maybe, args.joined(separator: " "))
            XCTAssertTrue(c.evidence.networkServer)
            XCTAssertTrue(c.why.contains("listens on the network"))
        }
        // A server inside a shell string is read word by word.
        let wrapped = Fx.proc(500, path: "/bin/sh", argv: ["sh", "-c", "mcp-server-x --port 8080"])
        XCTAssertEqual(Fx.tier(wrapped), .maybe)
        // A stdio listener for the Codex helper is still a Ghost.
        XCTAssertEqual(Fx.tier(Fx.proc(501, path: "/usr/local/bin/codex", argv: ["codex", "app-server", "--listen", "stdio://"])), .ghost)
    }

    func testAnIDEHostCountsOnlyWhenItsFolderMatches() {
        let cursor = Fx.proc(700, path: "/Applications/Cursor.app/Contents/MacOS/Cursor", argv: ["Cursor"], cwd: "/", root: nil)
        XCTAssertEqual(Fx.tier(Fx.mcp(500), with: [cursor]), .ghost)
        let cursorInFoo = Fx.proc(700, path: "/Applications/Cursor.app/Contents/MacOS/Cursor", argv: ["Cursor"])
        XCTAssertEqual(Fx.tier(Fx.mcp(500), with: [cursorInFoo]), .maybe)
    }

    func testStdinState() {
        XCTAssertEqual(Fx.tier(Fx.mcp(500, stdin: .writerAlive)), .maybe)
        XCTAssertEqual(Fx.tier(Fx.mcp(500, stdin: .writerGone)), .ghost, "writerGone never promotes or demotes")
        XCTAssertEqual(Fx.tier(Fx.mcp(500, age: 60, stdin: .writerGone)), .maybe, "writerGone does not bypass the age gate")
        XCTAssertTrue(Fx.classify(Fx.mcp(500, stdin: .writerAlive)).why.contains("other end of its input pipe"))
    }

    func testGenericSignaturesNeverGoAboveMaybe() {
        let bare = Fx.proc(500, argv: ["node", "/opt/tools/bin/mcp"])
        let c = Fx.classify(bare)
        XCTAssertEqual(c.evidence.signatureID, "mcp-bare")
        XCTAssertEqual(c.tier, .maybe)
        XCTAssertEqual(c.why, "Parent is gone. Matches a generic pattern, so Overstay is not sure.")
    }

    func testNoSignatureMeansIgnored() {
        XCTAssertEqual(Fx.tier(Fx.proc(500, argv: ["node", "server.js"])), .ignored)
        XCTAssertEqual(Fx.tier(Fx.proc(500, path: "/usr/bin/vim", argv: ["vim", "mcp-server-notes.md"])), .ignored)
    }

    func testChildrenOfALeftoverTreeAreLeftoversToo() {
        let wrapper = Fx.proc(500, path: "/bin/sh", argv: ["sh", "-c", "mcp-server-time /Users/jane/dev/foo"])
        let leaf = Fx.mcp(501, tag: "time", ppid: 500)
        XCTAssertEqual(Fx.tier(leaf, with: [wrapper]), .ghost)
        XCTAssertEqual(Fx.tier(wrapper, with: [leaf]), .ghost)
        // A parent that is not itself a signature match ends the chain: the child belongs to a running program.
        let plain = Fx.proc(500, argv: ["node", "supervisor.js"])
        XCTAssertEqual(Fx.tier(Fx.mcp(501, ppid: 500), with: [plain]), .ignored)
        // A parent that is a live agent session ends it too.
        XCTAssertEqual(Fx.tier(Fx.mcp(501, ppid: 400), with: [Fx.claude(400, ppid: 850)]), .ignored)
    }

    /// The usual npx leftover: `npm exec <pkg>` (title rewritten, parent launchd) > `sh -c <bin>` > `node <bin>`.
    func testNpxLeftoverTreeIsAllGhosts() {
        let wrapper = Fx.proc(500, argv: ["npm exec @upstash/context7-mcp@latest"])
        let sh = Fx.proc(501, ppid: 500, path: "/bin/sh", argv: ["sh", "-c", "context7-mcp"])
        let leaf = Fx.proc(502, ppid: 501, argv: ["node", "/Users/jane/.npm/_npx/ab/node_modules/.bin/context7-mcp"])
        for p in [wrapper, sh, leaf] {
            XCTAssertEqual(Fx.tier(p, with: [wrapper, sh, leaf].filter { $0.pid != p.pid }), .ghost, "pid \(p.pid)")
        }
    }

    /// A child never outranks its parent: under a Maybe wrapper (deliberate, young, generic, live session) a helper is a Maybe.
    func testChildrenInheritTheirParentsDowngrades() {
        let browser = Fx.proc(520, ppid: 500, path: "/Users/jane/.cache/puppeteer/chrome/mac_arm-126/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
                              argv: ["Google Chrome for Testing", "--headless=new", "--remote-debugging-pipe"], cwd: "/", root: nil)
        let alone = Fx.proc(520, path: browser.path, argv: browser.argv, cwd: "/", root: nil)
        XCTAssertEqual(Fx.tier(alone), .ghost)
        let wrappers: [(String, ProcessSnapshot, [ProcessSnapshot])] = [
            ("network", Fx.proc(500, argv: ["node", "/x/node_modules/.bin/mcp-server-x", "--port", "8080"]), []),
            ("young", Fx.mcp(500, age: 60), []),
            ("generic", Fx.proc(500, argv: ["node", "/opt/tools/bin/mcp"]), []),
            ("live session", Fx.mcp(500), [Fx.claude(400)]),
        ]
        for (name, wrapper, extra) in wrappers {
            XCTAssertEqual(Fx.tier(wrapper, with: extra), .maybe, name)
            XCTAssertEqual(Fx.tier(browser, with: [wrapper] + extra), .maybe, name)
        }
        // Under a Ghost wrapper it stays a Ghost.
        XCTAssertEqual(Fx.tier(browser, with: [Fx.mcp(500)]), .ghost)
    }

    func testFixedRemoteDebuggingPortIsDeliberate() {
        func chrome(_ flag: String) -> ProcessSnapshot {
            Fx.proc(520, path: "/Users/jane/.cache/puppeteer/chrome/mac_arm-126/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
                    argv: ["Google Chrome for Testing", "--headless=new", flag], cwd: "/", root: nil)
        }
        XCTAssertEqual(Fx.tier(chrome("--remote-debugging-port=9222")), .maybe)
        XCTAssertEqual(Fx.tier(chrome("--remote-debugging-address=0.0.0.0")), .maybe)
        XCTAssertEqual(Fx.tier(chrome("--remote-debugging-port=0")), .ghost)
        XCTAssertEqual(Fx.tier(chrome("--remote-debugging-pipe")), .ghost)
    }

    func testAgentSessionsAreProtectedNotListed() {
        let c = Fx.classify(Fx.claude(400, ppid: 1))
        XCTAssertEqual(c.tier, .protected)
        XCTAssertEqual(c.agent, .claudeCode)
        XCTAssertEqual(c.why, "Protected: an agent session.")
        // Even a Claude Code `mcp serve` run through node is a session, not an MCP server.
        let serve = Fx.proc(401, argv: ["node", "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js", "mcp", "serve"])
        XCTAssertEqual(Fx.classify(serve).evidence.signatureID, "claude-session")
        XCTAssertEqual(Fx.tier(serve), .protected)
    }

    func testAutomationBrowserIsAGhostButTheUsersChromeNever() {
        let headless = Fx.proc(520, path: "/Users/jane/.cache/puppeteer/chrome/mac_arm-126/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
                               argv: ["Google Chrome for Testing", "--headless=new", "--remote-debugging-port=0"], cwd: "/", root: nil)
        let c = Fx.classify(headless)
        XCTAssertEqual(c.tier, .ghost)
        XCTAssertEqual(c.agent, .automationBrowser)
        let normal = Fx.proc(521, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", argv: ["Google Chrome"], cwd: "/", root: nil)
        XCTAssertEqual(Fx.tier(normal), .protected)
        // Even with automation-looking flags, the user's Chrome needs the dedicated profile token.
        let flagged = Fx.proc(522, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                              argv: ["Google Chrome", "--remote-debugging-pipe"], cwd: "/", root: nil)
        XCTAssertEqual(Fx.tier(flagged), .protected)
    }

    func testAttributionComesFromTheSignatureThenFromAnEnvMarker() {
        XCTAssertEqual(Fx.classify(Fx.mcp(500)).agent, .unattributed)
        let marked = Fx.classify(Fx.mcp(500, env: ["CLAUDECODE"]))
        XCTAssertEqual(marked.agent, .claudeCode)
        XCTAssertEqual(marked.evidence.envMarker, "CLAUDECODE")
        XCTAssertEqual(Fx.classify(Fx.mcp(500, env: ["SOMETHING_ELSE"])).agent, .unattributed)
        let worker = Fx.proc(501, path: "/usr/local/bin/codex", argv: ["codex", "app-server", "--listen", "stdio://"])
        XCTAssertEqual(Fx.classify(worker).evidence.signatureID, "codex-app-server")
        XCTAssertEqual(Fx.classify(worker).agent, .codex)
    }

    func testAnotherUsersProcessIsProtectedAndNeverListed() {
        let theirs = Fx.mcp(500)
        var other = theirs
        other.uid = 502
        XCTAssertEqual(Fx.tier(other), .protected)
        let all = Classifier.classifyAll(Fx.world([other, Fx.mcp(501)]), prefs: .default, now: Fx.now)
        XCTAssertFalse(all.contains { $0.process.pid == 500 })
    }

    func testYoungMaybeNeedsAnExtraConfirmation() {
        let young = Fx.classify(Fx.mcp(500, age: 3600), with: [Fx.claude(400)])
        XCTAssertEqual(young.tier, .maybe)
        XCTAssertTrue(Classifier.requiresYoungConfirmation(young, prefs: .default, now: Fx.now))
        let old = Fx.classify(Fx.mcp(500, age: 25 * 3600), with: [Fx.claude(400)])
        XCTAssertEqual(old.tier, .maybe)
        XCTAssertFalse(Classifier.requiresYoungConfirmation(old, prefs: .default, now: Fx.now))
        let ghost = Fx.classify(Fx.mcp(500))
        XCTAssertFalse(Classifier.requiresYoungConfirmation(ghost, prefs: .default, now: Fx.now))
        XCTAssertFalse(Classifier.requiresYoungConfirmation(young, prefs: Preferences(confirmYoungerThanHours: 0), now: Fx.now))
    }

    func testCorruptPreferencesAndClocksDoNotTrap() {
        let young = Fx.classify(Fx.mcp(500, age: 3600), with: [Fx.claude(400)])
        XCTAssertTrue(Classifier.requiresYoungConfirmation(young, prefs: Preferences(confirmYoungerThanHours: Int.max), now: Fx.now))
        XCTAssertFalse(Classifier.requiresYoungConfirmation(young, prefs: Preferences(confirmYoungerThanHours: Int.min), now: Fx.now))
        XCTAssertEqual(Preferences(confirmYoungerThanHours: Int.max).confirmYoungerThanSeconds, 8760 * 3600)
        let p = Fx.mcp(500)
        XCTAssertEqual(p.age(at: Date(timeIntervalSince1970: .infinity)), 1_000_000_000_000)
        XCTAssertEqual(p.age(at: Date(timeIntervalSince1970: -.infinity)), 0)
        XCTAssertEqual(p.age(at: Date(timeIntervalSince1970: .nan)), 0)
        var far = p
        far.startSeconds = Int64.min
        XCTAssertEqual(far.age(at: Fx.now), 1_000_000_000_000)
    }

    func testUnreadableExecutablePathIsNeverAGhost() {
        var p = Fx.mcp(500)
        XCTAssertEqual(Fx.tier(p), .ghost)
        p.path = ""
        XCTAssertEqual(Fx.tier(p), .ignored, "argv alone must not make a Ghost")
    }

    func testClassifyAllIsInPidOrderAndSameUserOnly() {
        let all = Classifier.classifyAll(Fx.world([Fx.mcp(700), Fx.mcp(600)]), prefs: .default, now: Fx.now)
        XCTAssertEqual(all.map(\.process.pid), all.map(\.process.pid).sorted())
        XCTAssertTrue(all.allSatisfy { $0.process.uid == Fx.uid })
    }

    func testEveryTierHasAWhyLine() {
        let all = Classifier.classifyAll(Fx.world([Fx.mcp(500), Fx.mcp(501, age: 30), Fx.claude(), Fx.proc(502, argv: ["x"])]),
                                         prefs: .default, now: Fx.now)
        XCTAssertTrue(all.allSatisfy { !$0.why.isEmpty })
    }
}
