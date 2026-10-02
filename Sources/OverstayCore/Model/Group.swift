import Foundation

/// A project folder: the nearest `.git` ancestor of a process's cwd (or the cwd itself when there is none).
public struct Project: Codable, Hashable, Sendable {
    /// Folder name only, e.g. "foo". This is the only project text the activity log and the share card may carry.
    public var name: String
    /// Absolute path. In memory and on screen only; never logged, never on a share card unless the user opts in.
    public var root: String

    public init(name: String, root: String) {
        self.name = name
        self.root = root
    }
}

/// Everything one agent left behind in one project. Named `LeftoverGroup` so it never collides with SwiftUI's `Group`.
public struct LeftoverGroup: Codable, Hashable, Sendable, Identifiable {
    /// `LeftoverGroup.makeID(agent:projectRoot:)`. Stable across scans, so selection survives a refresh.
    public var id: String
    public var agent: AgentKind
    /// nil when the processes had no readable cwd.
    public var project: Project?
    /// Ghosts and Maybes only, parents before children.
    public var processes: [ClassifiedProcess]

    public init(id: String, agent: AgentKind, project: Project?, processes: [ClassifiedProcess]) {
        self.id = id
        self.agent = agent
        self.project = project
        self.processes = processes
    }

    public static func makeID(agent: AgentKind, projectRoot: String?) -> String {
        "\(agent.rawValue)|\(projectRoot ?? "-")"
    }

    public var ghosts: [ClassifiedProcess] { processes.filter { $0.tier == .ghost } }
    public var maybes: [ClassifiedProcess] { processes.filter { $0.tier == .maybe } }
    public var ghostCount: Int { processes.reduce(0) { $0 + ($1.tier == .ghost ? 1 : 0) } }
    public var maybeCount: Int { processes.count - ghostCount }
    /// Memory the Ghosts hold. Maybes are not counted: they are not part of any bulk action. Counts the listed processes
    /// only: helpers they spawn (a headless browser's renderer and GPU processes) are not added, so this understates.
    public var ghostBytes: UInt64 { processes.reduce(0) { $0 + ($1.tier == .ghost ? $1.process.footprintBytes : 0) } }
    public var totalBytes: UInt64 { processes.reduce(0) { $0 + $1.process.footprintBytes } }
    /// Earliest start among the Ghosts, or among all members when there are no Ghosts. For "started 3 days ago".
    public var oldestStart: Date? {
        let pool = ghostCount > 0 ? ghosts : processes
        return pool.map(\.process.startDate).min()
    }
}
