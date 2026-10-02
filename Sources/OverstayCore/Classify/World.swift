import Foundation

/// Everything the classifier knows about one scan: the process table, who we are, and who hosts us.
public struct World: Sendable {
    public let selfPid: Int32
    public let uid: UInt32
    public let home: String
    public let byPid: [Int32: ProcessSnapshot]
    public let children: [Int32: [Int32]]
    /// The ppid chain of `selfPid` up to (excluding) 1, loop-safe, at most 64 steps. Never signalled.
    public let ancestors: Set<Int32>
    private let agentRoots: [ProcessSnapshot]

    public init(_ raw: RawScan) {
        selfPid = raw.selfPid
        uid = raw.uid
        home = raw.home
        let table = Dictionary(raw.processes.map { ($0.pid, $0) }, uniquingKeysWith: { _, last in last })
        byPid = table
        var kids: [Int32: [Int32]] = [:]
        for p in table.values { kids[p.ppid, default: []].append(p.pid) }
        for k in kids.keys { kids[k]?.sort() }
        children = kids
        var up = Set<Int32>()
        var cur = table[raw.selfPid]?.ppid
        var steps = 0
        while let c = cur, c > 1, c != raw.selfPid, !up.contains(c), steps < 64 {
            up.insert(c)
            cur = table[c]?.ppid
            steps += 1
        }
        ancestors = up
        agentRoots = table.values.filter { $0.uid == raw.uid && Signatures.match($0)?.kind == .agentRoot }
            .sorted { $0.pid < $1.pid }
    }

    /// Running agent sessions (same user) that work in the same project as `p`: equal project roots, or, when either has
    /// none, equal working folders (never "/"). An IDE with an unknown workspace therefore makes nothing live.
    public func liveSessionPids(for p: ProcessSnapshot) -> [Int32] {
        agentRoots.filter { $0.pid != p.pid && Self.sameProject($0, p) }.map(\.pid)
    }

    static func sameProject(_ a: ProcessSnapshot, _ b: ProcessSnapshot) -> Bool {
        if let x = a.projectRoot, let y = b.projectRoot { return x == y }
        if let x = a.cwd, let y = b.cwd, !x.isEmpty, x != "/" { return x == y }
        return false
    }

    /// True when a process with pid `sid` exists and could be the leader of that session. A leader whose own session id
    /// is unknown counts as alive: the protected direction.
    public func isSessionLeaderAlive(_ sid: Int32) -> Bool {
        guard let leader = byPid[sid] else { return false }
        return leader.isSessionLeader || leader.sid == nil || leader.sid == sid
    }
}
