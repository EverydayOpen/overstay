import Foundation

public enum Classifier {
    /// Pure. One process, judged in the context of the whole scan. Order of decisions (first match wins):
    /// protected, wrong user or unreadable, no signature, agent session, not orphaned, then Ghost or Maybe.
    public static func classify(_ p: ProcessSnapshot, in world: World, prefs: Preferences, now: Date) -> ClassifiedProcess {
        let sig = Signatures.match(p)
        let project = ProjectNamer.project(projectRoot: p.projectRoot, cwd: p.cwd, home: world.home)?.name
        var e = SignalEvidence(signatureID: sig?.id, signatureStrength: sig?.strength, ageSeconds: p.age(at: now),
                               stdin: p.stdin)
        func done(_ tier: Classification, _ agent: AgentKind) -> ClassifiedProcess {
            ClassifiedProcess(process: p, tier: tier, agent: agent, evidence: e,
                              why: Why.line(e, tier: tier, signatureTitle: sig?.title, project: project,
                                            gateSeconds: prefs.ageGateSeconds))
        }
        if let r = Protected.reason(for: p, in: world, prefs: prefs) {
            e.protectedReason = r
            return done(.protected, sig?.agent ?? .unattributed)
        }
        // No readable path: every path-based protection would be blind, so argv alone never makes a Ghost.
        if p.uid != world.uid || p.path.isEmpty { return done(.ignored, .unattributed) }
        guard let sig else { return done(.ignored, .unattributed) }
        if sig.kind == .agentRoot {
            e.protectedReason = "an agent session"
            return done(.protected, sig.agent)
        }
        e.orphaned = isOrphaned(p, in: world, prefs: prefs)
        var agent = sig.agent
        if agent == .unattributed, let m = p.envMarkers.first(where: { EnvMarkers.agent(for: $0) != nil }) {
            e.envMarker = m
            agent = EnvMarkers.agent(for: m) ?? .unattributed
        }
        guard e.orphaned else { return done(.ignored, agent) }
        // A child inherits its parent's downgrades: under a Maybe (a deliberate server, a young or live-session tree) it is a Maybe.
        let parentOK = p.ppid == 1 || (world.byPid[p.ppid].map { classify($0, in: world, prefs: prefs, now: now).tier == .ghost } ?? false)
        e.liveSessionPids = world.liveSessionPids(for: p)
        // The live-session test compares projects, so it proves nothing for a process with no project (unreadable, or cwd "/"):
        // fail closed. cwd == home still matches a session in home. Automation browsers have no project by nature and a
        // live session cannot own one, so a known cwd is enough for them.
        e.projectUnknown = ProjectNamer.project(projectRoot: p.projectRoot, cwd: p.cwd, home: world.home) == nil
            && p.cwd != world.home && !(sig.kind == .automationBrowser && p.cwd != nil)
        e.networkServer = listensOnNetwork(p.argv)
        e.ageGateMet = e.ageSeconds >= prefs.ageGateSeconds
        let isGhost = sig.strength == .specific && e.liveSessionPids.isEmpty && e.ageGateMet && !e.projectUnknown
            && !e.networkServer && p.stdin != .writerAlive && parentOK
        return done(isGhost ? .ghost : .maybe, agent)
    }

    /// Every same-user process, in pid order; callers keep the listed ones.
    public static func classifyAll(_ world: World, prefs: Preferences, now: Date) -> [ClassifiedProcess] {
        world.byPid.values.filter { $0.uid == world.uid }.sorted { $0.pid < $1.pid }
            .map { classify($0, in: world, prefs: prefs, now: now) }
    }

    /// `--port`, `--host`, `--sse`, `--remote-debugging-address`, `--remote-debugging-port=N` (N not 0), `--transport X` (X not stdio) or `--listen ws:// | http://`: a daemonised network server may be
    /// run on purpose, so it never goes above Maybe. Reads words, not tokens, so `sh -c "server --port 80"` counts too.
    static func listensOnNetwork(_ argv: [String]) -> Bool {
        let words = argv.flatMap { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init) }
        for (i, w) in words.enumerated() {
            let parts = w.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let value = parts.count > 1 ? String(parts[1]) : (i + 1 < words.count ? words[i + 1] : "")
            switch String(parts[0]) {
            case "--port", "--host", "--sse", "--remote-debugging-address": return true
            case "--remote-debugging-port": if value != "0" { return true }   // port 0 is random: puppeteer's default
            case "--transport": if value != "stdio" { return true }
            case "--listen": if ["ws://", "wss://", "http://", "https://"].contains(where: value.hasPrefix) { return true }
            default: break
            }
        }
        return false
    }

    /// A Maybe younger than `prefs.confirmYoungerThanHours` needs an extra tick before a single stop.
    public static func requiresYoungConfirmation(_ c: ClassifiedProcess, prefs: Preferences, now: Date) -> Bool {
        c.tier == .maybe && c.process.age(at: now) < prefs.confirmYoungerThanSeconds
    }

    /// Parent is launchd. A child counts as orphaned too when everything above it, up to a launchd child, is itself a
    /// signature-matched, unprotected, same-user process (the tree an agent left behind). PPID 1 alone proves nothing;
    /// the caller combines this with the signature.
    static func isOrphaned(_ p: ProcessSnapshot, in world: World, prefs: Preferences) -> Bool {
        var cur = p
        var steps = 0
        while cur.ppid != 1 {
            guard steps < 64, let parent = world.byPid[cur.ppid], parent.pid != cur.pid, parent.uid == world.uid,
                  let s = Signatures.match(parent), s.kind != .agentRoot,
                  Protected.reason(for: parent, in: world, prefs: prefs) == nil else { return false }
            cur = parent
            steps += 1
        }
        return true
    }
}
