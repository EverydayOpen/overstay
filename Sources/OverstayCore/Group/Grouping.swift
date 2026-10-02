import Foundation

public enum ProjectNamer {
    /// `projectRoot`, else `cwd`, never "/" or home itself; nil when neither is usable. `name` is the folder name only.
    public static func project(projectRoot: String?, cwd: String?, home: String) -> Project? {
        for candidate in [projectRoot, cwd] {
            guard var root = candidate, !root.isEmpty else { continue }
            if root.count > 1, root.hasSuffix("/") { root.removeLast() }
            let h = home.count > 1 && home.hasSuffix("/") ? String(home.dropLast()) : home
            if root == "/" || root == h { continue }
            let name = PathText.basename(root)
            if !name.isEmpty { return Project(name: name, root: root) }
        }
        return nil
    }
}

enum Forest {
    /// Number of ancestors of `pid` that are in `parent`'s key set, following ppid. Loop-safe.
    static func depth(of pid: Int32, parent: [Int32: Int32]) -> Int {
        var d = 0
        var cur = parent[pid]
        while let c = cur, parent[c] != nil, d < 64 {
            d += 1
            cur = parent[c]
        }
        return d
    }
}

public enum Grouping {
    /// Listed (ghost/maybe) processes -> groups keyed by (agent, projectRoot ?? cwd). Groups sorted by ghostBytes desc,
    /// then totalBytes desc, then title, then id. Members sorted parents-before-children, then pid.
    public static func groups(_ listed: [ClassifiedProcess], home: String) -> [LeftoverGroup] {
        var buckets: [String: (agent: AgentKind, project: Project?, members: [ClassifiedProcess])] = [:]
        for c in listed where c.tier.isListed {
            let project = ProjectNamer.project(projectRoot: c.process.projectRoot, cwd: c.process.cwd, home: home)
            let id = LeftoverGroup.makeID(agent: c.agent, projectRoot: project?.root)
            buckets[id, default: (c.agent, project, [])].members.append(c)
        }
        return buckets.map { id, b in
            let parent = Dictionary(b.members.map { ($0.process.pid, $0.process.ppid) }, uniquingKeysWith: { a, _ in a })
            let ordered = b.members.sorted {
                let (da, db) = (Forest.depth(of: $0.process.pid, parent: parent), Forest.depth(of: $1.process.pid, parent: parent))
                return da != db ? da < db : $0.process.pid < $1.process.pid
            }
            return LeftoverGroup(id: id, agent: b.agent, project: b.project, processes: ordered)
        }.sorted {
            if $0.ghostBytes != $1.ghostBytes { return $0.ghostBytes > $1.ghostBytes }
            if $0.totalBytes != $1.totalBytes { return $0.totalBytes > $1.totalBytes }
            let (ta, tb) = (title($0), title($1))
            return ta != tb ? ta < tb : $0.id < $1.id
        }
    }

    /// "Claude Code", "Headless browsers"; an unattributed group reads "Agent tool servers".
    public static func title(_ g: LeftoverGroup) -> String { g.agent.displayName }
}
