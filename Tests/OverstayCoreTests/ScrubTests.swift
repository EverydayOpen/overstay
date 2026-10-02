import Foundation
import XCTest
@testable import OverstayCore

final class ScrubTests: XCTestCase {
    private let r = Scrub.redacted

    func testFlagValuesWithSecretNamesAreRedacted() {
        XCTAssertEqual(Scrub.token("--api-key=abc123"), "--api-key=\(r)")
        XCTAssertEqual(Scrub.token("--access-token=abc"), "--access-token=\(r)")
        XCTAssertEqual(Scrub.token("--Password=hunter2"), "--Password=\(r)")
        XCTAssertEqual(Scrub.token("--client-secret=x"), "--client-secret=\(r)")
        XCTAssertEqual(Scrub.token("--cookie=a=b"), "--cookie=\(r)")
        XCTAssertEqual(Scrub.token("--auth=Basic"), "--auth=\(r)")
    }

    func testTheValueAfterASecretFlagIsRedactedInArgv() {
        XCTAssertEqual(Scrub.argv(["node", "server.js", "--token", "s3cr3t", "--port", "80"]),
                       ["node", "server.js", "--token", r, "--port", "80"])
        // A following flag is not a value.
        XCTAssertEqual(Scrub.argv(["x", "--password", "--verbose"]), ["x", "--password", "--verbose"])
    }

    func testEnvironmentStyleAssignments() {
        XCTAssertEqual(Scrub.token("GITHUB_TOKEN=abcdef"), "GITHUB_TOKEN=\(r)")
        XCTAssertEqual(Scrub.token("my_password=abc"), "my_password=\(r)")
        XCTAssertEqual(Scrub.token("NODE_ENV=production"), "NODE_ENV=production")
        XCTAssertEqual(Scrub.token("SOME_BLOB=" + String(repeating: "q", count: 40)), "SOME_BLOB=\(r)")
        XCTAssertEqual(Scrub.token("lower=" + String(repeating: "q", count: 40)), "lower=" + String(repeating: "q", count: 40),
                       "only upper-case names get the long-value rule")
    }

    func testUrlCredentials() {
        XCTAssertEqual(Scrub.token("https://jane:pw@example.com/x"), "https://\(r)@example.com/x")
        XCTAssertEqual(Scrub.token("postgres://user@host/db"), "postgres://\(r)@host/db")
        XCTAssertEqual(Scrub.token("https://example.com/a@b"), "https://example.com/a@b", "an @ after the first slash is not credentials")
        XCTAssertEqual(Scrub.token("--url=https://jane:pw@example.com"), "--url=https://\(r)@example.com")
    }

    func testSecretsInUrlQueriesAndFragments() {
        XCTAssertEqual(Scrub.token("https://x.example/sse?token=abc123"), "https://x.example/sse?token=\(r)")
        XCTAssertEqual(Scrub.token("https://x.example/sse?page=2&api_key=abc"), "https://x.example/sse?page=2&api_key=\(r)")
        XCTAssertEqual(Scrub.token("https://x.example/cb?access_token=abc&state=1"), "https://x.example/cb?access_token=\(r)&state=1")
        XCTAssertEqual(Scrub.token("https://x.example/cb#access_token=abc"), "https://x.example/cb#access_token=\(r)")
        XCTAssertEqual(Scrub.token("--url=https://x.example?key=abc"), "--url=https://x.example?key=\(r)")
        XCTAssertEqual(Scrub.token("URL=https://x.example?Secret=abc"), "URL=https://x.example?Secret=\(r)")
        XCTAssertEqual(Scrub.argv(["mcp-remote", "https://x.example/sse?api_key=abc"]), ["mcp-remote", "https://x.example/sse?api_key=\(r)"])
        XCTAssertEqual(Scrub.token("https://x.example/list?page=2"), "https://x.example/list?page=2")
        XCTAssertEqual(Scrub.token("a;key=1"), "a;key=1", "no query or fragment, no change")
    }

    func testKnownSecretPrefixes() {
        for s in ["sk-ant-api03-abcdefghijkl", "ghp_abcdefghijklmnop", "gho_abcdefghijklmnop", "github_pat_11ABCDEFG0abcdefgh",
                  "xoxb-1234-5678-abcdef", "xoxp-1234-5678-abcdef", "AK" + "IAABCDEFGHIJKLMNOP", "AIzaSyAbCdEfGhIjKlMn", "npm_abcdefghijklmnop",
                  "eyJhbGciOiJIUzI1NiJ9"] {
            XCTAssertEqual(Scrub.token(s), r, s)
            XCTAssertEqual(Scrub.token("--header=" + s), "--header=\(r)", s)
        }
        XCTAssertEqual(Scrub.token("sk-learn"), "sk-learn", "too short to be a key")
    }

    func testLongOpaqueRuns() {
        XCTAssertEqual(Scrub.token("a1b2c3d4e5f6a1b2c3d4e5f6a1b2"), r)
        XCTAssertEqual(Scrub.token("123e4567-e89b-12d3-a456-426614174000"), r)
        XCTAssertEqual(Scrub.token("short1a2b3"), "short1a2b3")
        XCTAssertEqual(Scrub.token("abcdefghijklmnopqrstuvwxyzabcdefgh"), "abcdefghijklmnopqrstuvwxyzabcdefgh", "no digits")
        XCTAssertEqual(Scrub.token("/Users/jane/dev/a1b2c3d4e5f6a1b2c3d4e5f6a1b2"), "/Users/jane/dev/a1b2c3d4e5f6a1b2c3d4e5f6a1b2", "has a slash")
        XCTAssertEqual(Scrub.token("pkg-with.dot-a1b2c3d4e5f6a1b2c3d4"), "pkg-with.dot-a1b2c3d4e5f6a1b2c3d4", "has a dot")
    }

    func testAuthorizationHeaders() {
        XCTAssertEqual(Scrub.token("Authorization: Bearer abc.def"), "Authorization: \(r) \(r)")
        XCTAssertEqual(Scrub.token("curl -H Basic dXNlcjpwdw=="), "curl -H Basic \(r)")
    }

    func testASecretAfterAFlagOrHeaderNameInsideOneTokenIsRedacted() {
        XCTAssertEqual(Scrub.token("curl --api-key SECRET x"), "curl --api-key \(r) x")
        XCTAssertEqual(Scrub.token("curl --header=x-api-key: SECRET"), "curl --header=x-api-key: \(r)")
        XCTAssertEqual(Scrub.token("authorization: SECRET"), "authorization: \(r)")
        XCTAssertEqual(Scrub.token("authorization:bearer SECRET"), "authorization:bearer \(r)")
        XCTAssertEqual(Scrub.token("X-API-Key:  SECRET"), "X-API-Key:  \(r)", "an empty word must not consume the flag")
        XCTAssertEqual(Scrub.token("run --api-key=abc next"), "run --api-key=\(r) next", "the value is already inline")
        XCTAssertEqual(Scrub.token("API_KEY=abc next"), "API_KEY=\(r) next")
    }

    func testPassAndPwdFlagNames() {
        XCTAssertEqual(Scrub.token("--passphrase=x"), "--passphrase=\(r)")
        XCTAssertEqual(Scrub.token("--pwd=x"), "--pwd=\(r)")
        XCTAssertEqual(Scrub.argv(["openssl", "x", "-passin", "pass:x"]), ["openssl", "x", "-passin", r])
    }

    func testShellScriptsAreScrubbedWordByWord() {
        XCTAssertEqual(Scrub.token("cd /x && API_KEY=abc npx mcp-server-time"), "cd /x && API_KEY=\(r) npx mcp-server-time")
    }

    func testPackageNamesPathsAndFlagNamesSurvive() {
        let kept = ["@modelcontextprotocol/server-filesystem", "@playwright/mcp@latest", "chrome-devtools-mcp", "mcp-server-git",
                    "/Users/jane/.npm/_npx/ab12cd34/node_modules/.bin/mcp-server-git", "--remote-debugging-pipe", "--headless=new",
                    "--user-data-dir=/var/folders/zz/T/playwright_chromiumdev_profile-AbCdEf", "uvx", "-y", "stdio://",
                    "--stdio", "https://example.com/mcp", "context7-mcp", "mcp_server_git"]
        for k in kept { XCTAssertEqual(Scrub.token(k), k) }
        XCTAssertEqual(Scrub.argv(kept).count, min(kept.count, Scrub.maxArgs))
        XCTAssertEqual(Scrub.argv(kept), Array(kept.prefix(Scrub.maxArgs)))
    }

    func testArgvCapLeavesRoomForLongBrowserLaunches() {
        XCTAssertGreaterThanOrEqual(Scrub.maxArgs, 100)
        let flags = (0..<60).map { "--flag-\($0)" } + ["--headless"]
        XCTAssertEqual(Scrub.argv(flags), flags)
    }

    func testElementZeroIsScrubbedAndCleaned() {
        XCTAssertEqual(Scrub.argv(["GITHUB_TOKEN=abc", "x"]), ["GITHUB_TOKEN=\(r)", "x"], "the parser can shift argv[1] into slot 0")
        XCTAssertEqual(Scrub.argv(["a\u{0}b\nc"]), ["a b c"])
    }

    func testBase64WithSlashesIsOpaqueButPathsSurvive() {
        // Built from pieces so secret scanners do not flag this fake value.
        let aws = "wJalrXUtnFEMI/" + "K7MDENG/bPxRf1CY3XAMPL4KEY"
        XCTAssertEqual(Scrub.token(aws), r)
        XCTAssertEqual(Scrub.token("--x=" + aws), "--x=\(r)")
        for k in ["src/components/v2/Button", "node_modules/.bin/x", "~/dev/a1b2c3d4e5f6a1b2c3d4e5f6a1b2", "./a1b2c3d4e5f6a1b2c3d4e5f6a1b2"] {
            XCTAssertEqual(Scrub.token(k), k)
        }
    }

    func testCapsAndControlCharacters() {
        let long = Array(repeating: "x", count: 300)
        XCTAssertEqual(Scrub.argv(long).count, Scrub.maxArgs)
        let big = String(repeating: "z", count: 500)
        XCTAssertEqual(Scrub.token(big).count, Scrub.maxTokenLength)
        XCTAssertTrue(Scrub.token(big).hasSuffix("…"))
        XCTAssertEqual(Scrub.token("a\tb\u{7}c"), "a b c")
        XCTAssertEqual(Scrub.token(""), "")
        XCTAssertEqual(Scrub.argv([]), [])
    }

    func testASecretCannotSurviveByStraddlingTheClipBoundary() {
        let token = "--api-key=" + String(repeating: "S", count: 300)
        XCTAssertEqual(Scrub.token(token), "--api-key=\(r)")
    }

    func testTilde() {
        XCTAssertEqual(Scrub.tilde("/Users/jane/dev/foo", home: "/Users/jane"), "~/dev/foo")
        XCTAssertEqual(Scrub.tilde("/Users/jane", home: "/Users/jane"), "~")
        XCTAssertEqual(Scrub.tilde("/Users/janet/x", home: "/Users/jane"), "/Users/janet/x")
        XCTAssertEqual(Scrub.tilde("/opt/x", home: "/Users/jane"), "/opt/x")
        XCTAssertEqual(Scrub.tilde("/opt/x", home: ""), "/opt/x")
    }
}
