import Foundation

/// The tier a process lands in (BUILD_PLAN §4.2 has the rules).
public enum Classification: String, Codable, CaseIterable, Sendable {
    /// Matches a signature, orphaned, no live agent session owns it, old enough. Pre-selected in bulk stops.
    case ghost
    /// Matches a signature and is orphaned, but a session may still use it, or it is too young, or the signature is generic.
    /// Shown, never pre-selected, never part of a bulk action.
    case maybe
    /// Everything else. Never listed.
    case ignored
    /// On the hard-coded protected list, or our own ancestry. Never listed, never selectable, never signalled.
    case protected

    /// Appears in the UI.
    public var isListed: Bool { self == .ghost || self == .maybe }
}

/// The facts behind one classification. `Why.line(_:)` turns them into the one-line explanation.
public struct SignalEvidence: Codable, Hashable, Sendable {
    /// `ppid == 1`. Meaningless alone (every launchd-started app has it); counts only together with a signature.
    public var orphaned: Bool
    public var signatureID: String?
    public var signatureStrength: Strength?
    /// Pids of running agent root processes that share this process's project (or cwd): the "live session" test.
    public var liveSessionPids: [Int32]
    public var ageSeconds: Int
    public var ageGateMet: Bool
    /// Set exactly when the tier is `.protected`: the human reason ("inside an app bundle", "terminal session is alive").
    public var protectedReason: String?
    /// Name of the allow-listed environment key that hinted at the agent, if any. Never its value.
    public var envMarker: String?
    public var stdin: StdinState
    /// Neither a working folder nor a project root could be read, so a live session in the same project cannot be ruled out.
    public var projectUnknown: Bool
    /// argv asks for a network listener (`--port`, `--transport sse`, `--listen ws://`): probably started on purpose.
    public var networkServer: Bool

    public init(orphaned: Bool = false, signatureID: String? = nil, signatureStrength: Strength? = nil,
                liveSessionPids: [Int32] = [], ageSeconds: Int = 0, ageGateMet: Bool = false,
                protectedReason: String? = nil, envMarker: String? = nil, stdin: StdinState = .unknown,
                projectUnknown: Bool = false, networkServer: Bool = false) {
        self.orphaned = orphaned
        self.signatureID = signatureID
        self.signatureStrength = signatureStrength
        self.liveSessionPids = liveSessionPids
        self.ageSeconds = ageSeconds
        self.ageGateMet = ageGateMet
        self.protectedReason = protectedReason
        self.envMarker = envMarker
        self.stdin = stdin
        self.projectUnknown = projectUnknown
        self.networkServer = networkServer
    }
}

public struct ClassifiedProcess: Codable, Hashable, Sendable, Identifiable {
    public var process: ProcessSnapshot
    public var tier: Classification
    public var agent: AgentKind
    public var evidence: SignalEvidence
    /// One plain-English line, e.g. "Parent is gone, looks like an MCP server, no live session in this project."
    public var why: String

    public init(process: ProcessSnapshot, tier: Classification, agent: AgentKind, evidence: SignalEvidence, why: String) {
        self.process = process
        self.tier = tier
        self.agent = agent
        self.evidence = evidence
        self.why = why
    }

    public var id: Int32 { process.pid }
}
