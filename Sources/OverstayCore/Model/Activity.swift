import Foundation

/// One line of the append-only activity log (JSONL, `ActivityLog.encode`). One per target, including skipped and failed
/// ones. Deliberately small (BUILD_PLAN §3 rule 8): no argv, no environment, no full paths.
public struct ActivityEntry: Codable, Hashable, Sendable, Identifiable {
    public var timestamp: Date
    /// `StopPlan.batchID`: the Stop click this line belongs to.
    public var batchID: String
    public var mode: StopMode
    public var pid: Int32
    /// Executable basename.
    public var executable: String
    public var signatureID: String
    public var agent: AgentKind
    /// Folder name only.
    public var project: String?
    public var footprintBytes: UInt64
    public var result: TargetStatus
    public var errno: Int32?
    /// The "why" line shown when the user approved it.
    public var why: String

    public init(timestamp: Date, batchID: String, mode: StopMode, pid: Int32, executable: String, signatureID: String,
                agent: AgentKind, project: String?, footprintBytes: UInt64, result: TargetStatus, errno: Int32? = nil,
                why: String) {
        self.timestamp = timestamp
        self.batchID = batchID
        self.mode = mode
        self.pid = pid
        self.executable = executable
        self.signatureID = signatureID
        self.agent = agent
        self.project = project
        self.footprintBytes = footprintBytes
        self.result = result
        self.errno = errno
        self.why = why
    }

    /// Unique enough for a list: a batch never holds one pid twice per mode.
    public var id: String { "\(batchID)-\(mode.rawValue)-\(pid)" }

    public init(_ outcome: TargetOutcome, batchID: String, mode: StopMode, at timestamp: Date) {
        self.init(timestamp: timestamp, batchID: batchID, mode: mode, pid: outcome.target.identity.pid,
                  executable: outcome.target.name, signatureID: outcome.target.signatureID, agent: outcome.target.agent,
                  project: outcome.target.projectName, footprintBytes: outcome.target.footprintBytes,
                  result: outcome.status, errno: outcome.errno, why: outcome.target.why)
    }
}
