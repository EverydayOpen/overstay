/// What kind of leftover a signature describes.
public enum SignatureKind: String, Codable, Sendable {
    /// A session's main process (the CLI, an IDE's agent host). Never a Ghost or Maybe itself; while it runs, its
    /// project counts as having a live session. Classified `.protected`.
    case agentRoot
    case mcpServer
    case agentWorker
    case automationBrowser
    case devTool
}

/// `.specific` signatures can make a Ghost. `.generic` ones (a bare `--stdio` server, an unrecognised launcher) never
/// go above Maybe.
public enum Strength: String, Codable, Sendable {
    case specific
    case generic
}

/// One test against a process. "Token" means one element of the scrubbed argv; "base" means its last path component
/// with a trailing `.js`, `.mjs`, `.cjs`, `.ts` or `.py` removed (`Matching.base`). All comparisons are case-sensitive.
public enum Pattern: Hashable, Sendable {
    case tokenContains(String)
    case tokenBaseEquals(String)
    case tokenBasePrefix(String)
    case tokenBaseSuffix(String)
    /// The token equals the flag, or starts with `flag=`.
    case flag(String)
    case pathContains(String)
    case nameEquals(String)
    /// Every pattern must match.
    case all([Pattern])
}

/// A row of the signature table (`Signatures.all`, plain data in `Sources/OverstayCore/Classify/Signatures.swift`).
/// Adding a signature is one line there plus one fixture.
public struct Signature: Hashable, Sendable, Identifiable {
    /// Stable, lowercase, hyphenated; written to the activity log, so never rename one.
    public var id: String
    /// Shown in the UI: "MCP server (filesystem)".
    public var title: String
    public var kind: SignatureKind
    public var agent: AgentKind
    public var strength: Strength
    /// Matches when any pattern matches.
    public var patterns: [Pattern]

    public init(_ id: String, _ title: String, kind: SignatureKind, agent: AgentKind = .unattributed,
                strength: Strength = .specific, _ patterns: [Pattern]) {
        self.id = id
        self.title = title
        self.kind = kind
        self.agent = agent
        self.strength = strength
        self.patterns = patterns
    }
}
