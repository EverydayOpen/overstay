import Foundation

/// argv is a secret until proven otherwise (BUILD_PLAN §3 rule 11). Everything here is applied before argv enters a
/// `ProcessSnapshot`; package names, paths and flag names a signature needs are left alone.
public enum Scrub {
    // Signatures match on this argv, and real Playwright/Puppeteer launches put --headless / --remote-debugging-pipe
    // 30+ flags in, so the cap must stay well above that. Display is clipped separately (`argvSummary`).
    public static let maxArgs = 128
    public static let maxTokenLength = 200
    public static let redacted = "<redacted>"

    private static let fragments = ["token", "secret", "pass", "pwd", "private", "key", "auth", "credential", "cookie", "bearer"]
    private static let prefixes = ["sk-", "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_", "xoxb-", "xoxa-", "xoxp-",
                                   "xoxs-", "AKIA", "AIza", "npm_", "eyJ"]

    // `?token=...`, `&api_key=...`, `#access_token=...` (also `;`-separated): the value of any secret-named query or fragment pair.
    private static let queryPair = "(?i)([?&;#][^=&;#?]*(?:" + fragments.joined(separator: "|") + ")[^=&;#?]*=)[^&;#]*"

    /// Applied by the Mac layer to raw argv. Every element is scrubbed (the parser can shift argv[1] into slot 0); flag
    /// names are kept and the value that follows a secret-looking flag (`--api-key VALUE`) is replaced. At most `maxArgs` elements.
    public static func argv(_ raw: [String]) -> [String] {
        var out: [String] = []
        var redactNext = false
        for t in raw.prefix(maxArgs) {
            if redactNext, !t.hasPrefix("-") {
                out.append(redacted)
                redactNext = false
                continue
            }
            redactNext = t.hasPrefix("-") && !t.contains("=") && secretName(t)
            out.append(token(t))
        }
        return out
    }

    /// One token. Replaces with "<redacted>": the value of `--flag=value` when the flag name contains token, secret,
    /// pass, pwd, private, key, auth, credential, cookie or bearer; the value of `NAME=value` on the same rule (and any
    /// upper-case `NAME=` with a value over 32 characters); `user:pass@` in URLs and the value of a secret-named `?name=`, `&name=` or `#name=` pair in a URL; known secret prefixes (sk-, ghp_, gho_,
    /// github_pat_, xox[bpas]-, AKIA, AIza, npm_, eyJ); any word of 24+ characters from [A-Za-z0-9_+=/-] holding a letter
    /// and at least three digits (no "." in it and no leading "/", "." or "~", so paths and package names survive); the word after
    /// `Bearer`, `Basic`, a secret-named flag or a `Header-Name:` with a secret-looking name. Control characters become
    /// spaces and the result is clipped to `maxTokenLength`. A token with spaces (a shell script) is scrubbed word by word.
    public static func token(_ t: String) -> String {
        var out: [String] = []
        var hide = false
        for w in clean(t).split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
            if hide && w.isEmpty { out.append(w); continue }
            out.append(hide ? redacted : word(w))
            // "Authorization: Bearer VALUE", "--api-key VALUE", "--header=x-api-key: VALUE"; judge a dash word by what follows "="
            let l = w.lowercased()
            let v = l.hasPrefix("-") ? String(l.split(separator: "=", maxSplits: 1).last ?? Substring(l)) : l
            hide = v == "basic" || (secretName(v) && (v.hasPrefix("-") || v.hasSuffix(":") || v.hasSuffix("bearer")))
        }
        return clip(out.joined(separator: " "))
    }

    /// "/Users/jane/dev/foo" -> "~/dev/foo" for display (not for matching).
    public static func tilde(_ path: String, home: String) -> String {
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private static func word(_ w: String) -> String {
        guard let eq = w.firstIndex(of: "=") else { return w.hasPrefix("-") ? w : value(w) }
        let name = String(w[..<eq])
        let v = String(w[w.index(after: eq)...])
        if w.hasPrefix("-") { return name + "=" + (secretName(name) ? redacted : value(v)) }
        if isEnvName(name) {
            if secretName(name) || (v.count > 32 && name == name.uppercased()) { return name + "=" + redacted }
            return name + "=" + value(v)
        }
        return value(w)
    }

    private static func value(_ v: String) -> String {
        var s = stripUserInfo(v)
        if s.contains("?") || s.contains("#") {
            s = s.replacingOccurrences(of: queryPair, with: "$1" + redacted, options: .regularExpression)
        }
        if s.count >= 12, prefixes.contains(where: s.hasPrefix) { return redacted }
        return isOpaque(s) ? redacted : s
    }

    private static func secretName(_ n: String) -> Bool {
        let l = n.lowercased()
        return fragments.contains(where: l.contains)
    }

    private static func isEnvName(_ n: String) -> Bool {
        guard let f = n.unicodeScalars.first, f == "_" || (f.isASCII && CharacterSet.letters.contains(f)) else { return false }
        return n.unicodeScalars.allSatisfy { $0 == "_" || ($0.isASCII && CharacterSet.alphanumerics.contains($0)) }
    }

    private static func stripUserInfo(_ v: String) -> String {
        guard let scheme = v.range(of: "://"), let at = v[scheme.upperBound...].firstIndex(of: "@"),
              !v[scheme.upperBound..<at].contains("/") else { return v }
        return String(v[..<scheme.upperBound]) + redacted + String(v[at...])
    }

    private static func isOpaque(_ s: String) -> Bool {
        guard s.count >= 24, !s.hasPrefix("/"), !s.hasPrefix("."), !s.hasPrefix("~") else { return false }
        var letters = 0, digits = 0
        for u in s.unicodeScalars {
            switch u.value {
            case 48...57: digits += 1
            case 65...90, 97...122: letters += 1
            case 43, 45, 47, 61, 95: break      // + - / = _
            default: return false
            }
        }
        return letters > 0 && digits >= 3
    }

    private static func clean(_ t: String) -> String {
        String(String.UnicodeScalarView(t.unicodeScalars.map { $0.value < 32 || $0.value == 127 ? Unicode.Scalar(32 as UInt8) : $0 }))
    }

    private static func clip(_ s: String) -> String { s.count <= maxTokenLength ? s : String(s.prefix(maxTokenLength - 1)) + "…" }
}
