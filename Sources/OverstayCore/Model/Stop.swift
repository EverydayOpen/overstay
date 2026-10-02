import Foundation

/// Which signal a plan sends. `.terminate` is the polite one and the default; `.force` exists only for survivors,
/// only after an explicit per-group click, and is the only path that may send the unblockable signal.
public enum StopMode: String, Codable, Sendable {
    case terminate
    case force
}

/// One process a plan will signal, with what the user saw when approving it.
public struct StopTarget: Codable, Hashable, Sendable, Identifiable {
    public var identity: ProcessIdentity
    /// Executable basename.
    public var name: String
    public var signatureID: String
    public var agent: AgentKind
    /// Folder name only.
    public var projectName: String?
    /// `.ghost` for a bulk stop, `.maybe` for a single confirmed Maybe. Verification never lets a Maybe through on a Ghost approval's behalf, and never lets a Ghost-approved target through once it has become a Maybe.
    public var approvedTier: Classification
    public var footprintBytes: UInt64
    /// Depth in the plan's process forest (roots 0). Deeper targets are signalled first.
    public var depth: Int
    /// The one-line explanation shown at approval time (for the log).
    public var why: String

    public init(identity: ProcessIdentity, name: String, signatureID: String, agent: AgentKind, projectName: String?,
                approvedTier: Classification, footprintBytes: UInt64, depth: Int, why: String) {
        self.identity = identity
        self.name = name
        self.signatureID = signatureID
        self.agent = agent
        self.projectName = projectName
        self.approvedTier = approvedTier
        self.footprintBytes = footprintBytes
        self.depth = depth
        self.why = why
    }

    public var id: Int32 { identity.pid }
}

/// Something the user selected that the plan will not touch, and why ("protected", "part of this app's own ancestry").
public struct SkippedTarget: Codable, Hashable, Sendable {
    public var pid: Int32
    public var name: String
    public var reason: String

    public init(pid: Int32, name: String, reason: String) {
        self.pid = pid
        self.name = name
        self.reason = reason
    }
}

public struct StopPlan: Codable, Hashable, Sendable {
    /// One per Stop click; ties the log lines together.
    public var batchID: String
    public var mode: StopMode
    public var groupIDs: [String]
    /// Already in signalling order: leaf-first.
    public var targets: [StopTarget]
    public var skipped: [SkippedTarget]
    /// How long to wait for the targets to exit before reporting survivors. 5 for `.terminate`, 2 for `.force`.
    public var graceSeconds: Double

    public init(batchID: String, mode: StopMode, groupIDs: [String], targets: [StopTarget],
                skipped: [SkippedTarget] = [], graceSeconds: Double = 5) {
        self.batchID = batchID
        self.mode = mode
        self.groupIDs = groupIDs
        self.targets = targets
        self.skipped = skipped
        self.graceSeconds = graceSeconds
    }

    public var totalFootprintBytes: UInt64 { targets.reduce(0) { $0 + $1.footprintBytes } }
}

public enum TargetStatus: String, Codable, Sendable {
    /// Exited within the grace period after the polite signal.
    case stopped
    /// Exited after the force signal.
    case forceStopped
    /// Still running after the grace period (offer Force stop), or still running after force.
    case survived
    /// Exited before we signalled it. Not our doing, so not counted as stopped or as memory held.
    case alreadyGone
    /// Verification failed: another start time, path, uid or signature, or no longer a Ghost/Maybe. Nothing sent.
    case changedSinceScan
    /// The system refused the signal (EPERM).
    case refused
    /// Our own guards said no (protected, own ancestry, own pid, pid 1 or below, another user). Nothing sent.
    case blocked
    /// Any other error from the signal call.
    case failed
    /// Write-ahead line, appended right before a signal is sent and followed by the real outcome. It lives only in
    /// the activity log, never in a `StopOutcome`; alone it means the app ended before the outcome was known.
    case signalled

    public var wasStopped: Bool { self == .stopped || self == .forceStopped }
}

public struct TargetOutcome: Codable, Hashable, Sendable, Identifiable {
    public var target: StopTarget
    public var status: TargetStatus
    /// errno from the signal call, when there was one.
    public var errno: Int32?
    /// Short plain text for `changedSinceScan` and `blocked`.
    public var detail: String?

    public init(target: StopTarget, status: TargetStatus, errno: Int32? = nil, detail: String? = nil) {
        self.target = target
        self.status = status
        self.errno = errno
        self.detail = detail
    }

    public var id: Int32 { target.id }
}

public struct StopOutcome: Codable, Hashable, Sendable {
    public var batchID: String
    public var mode: StopMode
    public var startedAt: Date
    public var finishedAt: Date
    public var results: [TargetOutcome]
    /// Copied from the plan so the result screen can say what was left alone.
    public var skipped: [SkippedTarget]

    public init(batchID: String, mode: StopMode, startedAt: Date, finishedAt: Date, results: [TargetOutcome],
                skipped: [SkippedTarget] = []) {
        self.batchID = batchID
        self.mode = mode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.results = results
        self.skipped = skipped
    }

    public var stoppedCount: Int { results.filter { $0.status.wasStopped }.count }
    /// Targets still running: the "Force stop" list.
    public var survivors: [StopTarget] { results.filter { $0.status == .survived }.map(\.target) }
    /// Sum of the stopped processes' physical footprint. "Held", not "freed": the system decides what that becomes.
    public var heldBytes: UInt64 { results.reduce(0) { $0 + ($1.status.wasStopped ? $1.target.footprintBytes : 0) } }
    /// Verification failures, refusals and blocks: everything that was not sent or not accepted.
    public var notSentCount: Int {
        results.filter { [.changedSinceScan, .refused, .blocked, .failed].contains($0.status) }.count
    }
}
