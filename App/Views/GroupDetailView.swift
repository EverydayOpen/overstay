import OverstayCore
import SwiftUI

/// One group: the process tree (parents before children) with a plain "why" per row, the scrubbed command and folder
/// behind a disclosure, and the Maybes collapsed underneath (docs/DESIGN.md §6.5). Read-only except "Stop this one…".
struct GroupDetailView: View {
    let group: LeftoverGroup
    /// The scan time, so ages are stable between rescans (and deterministic in demo mode).
    let now: Date
    let home: String

    var body: some View {
        let ghosts = Self.treeOrder(group.ghosts)
        let byPid = Dictionary(group.processes.map { ($0.process.pid, $0.process) }, uniquingKeysWith: { a, _ in a })
        let depths = Self.depths(group.processes, byPid: byPid)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                if !ghosts.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(ghosts.enumerated()), id: \.element.id) { i, c in
                            if i > 0 { Divider() }
                            DetailRow(c: c, depth: depths[c.process.pid] ?? 0, parent: byPid[c.process.ppid], home: home, now: now, index: i)
                        }
                    }
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.xs)
                    .surface(16)
                }
                if group.maybeCount > 0 {
                    MaybeSection(items: group.maybes, home: home, now: now, startOpen: ghosts.isEmpty, depths: depths, parents: byPid)
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            GroupGlyph(symbol: group.agent.symbol, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(Grouping.title(group)).font(.system(size: 22, weight: .semibold)).tracking(-0.3)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [group.project.map { Scrub.tilde($0.root, home: home) } ?? "No project folder"]
        if group.ghostCount > 0 { parts += ["\(group.ghostCount) leftover", Format.bytes(group.ghostBytes)] }
        if group.maybeCount > 0 { parts.append("\(group.maybeCount) Maybe") }
        if let start = group.oldestStart { parts.append(Format.started(seconds: Int(now.timeIntervalSince(start)))) }
        return parts.joined(separator: " · ")
    }

    /// Each parent followed by its own subtree, so an `npm`, `zsh`, `node` chain reads as one chain instead of every `npm`
    /// first. Roots keep the group's order (by pid); a loop in the table cannot hang it.
    private static func treeOrder(_ items: [ClassifiedProcess]) -> [ClassifiedProcess] {
        let pids = Set(items.map(\.process.pid))
        let kids = Dictionary(grouping: items.filter { pids.contains($0.process.ppid) && $0.process.ppid != $0.process.pid },
                              by: { $0.process.ppid })
        var out: [ClassifiedProcess] = []
        var seen = Set<Int32>()
        func visit(_ c: ClassifiedProcess) {
            guard seen.insert(c.process.pid).inserted else { return }
            out.append(c)
            for k in (kids[c.process.pid] ?? []).sorted(by: { $0.process.pid < $1.process.pid }) { visit(k) }
        }
        for c in items where !pids.contains(c.process.ppid) || c.process.ppid == c.process.pid { visit(c) }
        for c in items { visit(c) }
        return out
    }

    /// Depth of each member under its parent when the parent is in the group too. Loop-safe.
    private static func depths(_ members: [ClassifiedProcess], byPid: [Int32: ProcessSnapshot]) -> [Int32: Int] {
        var out: [Int32: Int] = [:]
        for m in members {
            var depth = 0
            var cur = m.process.ppid
            while depth < 32, let parent = byPid[cur], parent.pid != m.process.pid {
                depth += 1
                cur = parent.ppid
            }
            out[m.process.pid] = depth
        }
        return out
    }
}

/// The Maybes, collapsed. Each has its own "Stop this one…" and is never part of a bulk stop.
struct MaybeSection: View {
    let items: [ClassifiedProcess]
    let home: String
    let now: Date
    var showsProject = false
    var depths: [Int32: Int] = [:]
    var parents: [Int32: ProcessSnapshot] = [:]
    @State private var open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(items: [ClassifiedProcess], home: String, now: Date, startOpen: Bool = false, showsProject: Bool = false,
         depths: [Int32: Int] = [:], parents: [Int32: ProcessSnapshot] = [:]) {
        self.items = items
        self.home = home
        self.now = now
        self.showsProject = showsProject
        self.depths = depths
        self.parents = parents
        _open = State(initialValue: startOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button {
                withAnimation(Motion.standard(reduceMotion)) { open.toggle() }
            } label: {
                HStack(spacing: Space.xs) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold)).frame(width: 12)
                    Text("\(items.count) Maybe").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("Never part of a bulk stop").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(items.count) Maybe")
            .accessibilityValue(open ? "expanded" : "collapsed")
            if open {
                ForEach(items) { c in
                    Divider()
                    DetailRow(c: c, depth: depths[c.process.pid] ?? 0, parent: parents[c.process.ppid], home: home, now: now,
                              showsProject: showsProject, showsStop: true)
                }
            }
        }
        .padding(Space.m)
        .surface(16)
    }
}

/// One process: name, size, tier word, the plain "why", and a Details disclosure. The first eight rows of a group
/// flip in once on the 45 ms stagger (MOTION §3.4); everything below them is simply there.
struct DetailRow: View {
    let c: ClassifiedProcess
    let depth: Int
    let parent: ProcessSnapshot?
    let home: String
    let now: Date
    var index = 99
    var showsProject = false
    var showsStop = false
    @State private var open = false
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rails: Int { min(depth, 5) }
    private var animates: Bool { index < 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(RowRole.title(c))
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: Space.xs)
                Text(Format.bytes(c.process.footprintBytes))
                    .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                Tag(text: c.tier.word, tint: c.tier.tint)
            }
            Text(meta).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            if showsProject, let project = projectText {
                Text(project).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Text(c.why)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    withAnimation(Motion.standard(reduceMotion)) { open.toggle() }
                } label: {
                    Label(open ? "Hide Details" : "Details", systemImage: open ? "chevron.down" : "chevron.right").font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityValue(open ? "expanded" : "collapsed")
                Spacer()
                if showsStop && c.tier == .maybe { MaybeStopButton(c: c, now: now) }
            }
            if open { details }
        }
        .padding(.leading, CGFloat(rails) * 16)
        .padding(.vertical, Space.xs)
        .background(alignment: .leading) {
            HStack(spacing: 15) {
                ForEach(0..<rails, id: \.self) { _ in Rectangle().fill(.separator).frame(width: 1) }
            }
            .padding(.leading, 7)
        }
        .modifier(FlipIn(shown: arrived || !animates))
        .onAppear {
            guard animates, !arrived else { return }
            withAnimation(Motion.spring(reduceMotion).delay(reduceMotion ? 0 : Double(index) * Motion.stagger)) { arrived = true }
        }
        .accessibilityElement(children: .contain)
    }

    /// "npm · pid 20012 · started 3 days ago": what it runs as, which one, how long.
    private var meta: String {
        var parts: [String] = []
        if !c.process.name.isEmpty { parts.append(c.process.name) }
        parts.append("pid \(c.process.pid)")
        parts.append(Format.started(seconds: c.process.age(at: now)))
        return parts.joined(separator: " · ")
    }

    private var projectText: String? {
        ProjectNamer.project(projectRoot: c.process.projectRoot, cwd: c.process.cwd, home: home).map { Scrub.tilde($0.root, home: home) }
    }

    /// Where it came from, in words: a parent in this group, launchd, or just a pid.
    private var ancestry: String {
        if let parent { return "Started by \(parent.name), pid \(parent.pid), which is in this group." }
        if c.evidence.orphaned { return "Parent is gone, adopted by launchd." }
        return "Parent is pid \(c.process.ppid)."
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ancestry).font(.system(size: 12)).foregroundStyle(.secondary)
            field("Command", c.process.argv.isEmpty ? "Not readable" : c.process.argvSummary)
            if let cwd = c.process.cwd { field("Folder", Scrub.tilde(cwd, home: home)) }
            if !c.process.path.isEmpty { field("Program", Scrub.tilde(c.process.path, home: home)) }
        }
        .padding(Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    /// The command is already scrubbed (secret-looking values hidden) and capped before it gets here.
    private func field(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(label).font(.caption2.weight(.semibold).smallCaps()).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

/// A row's headline: what the signature matched, then the one word that tells siblings apart ("MCP server: filesystem",
/// "Codex helper: app server", "Automation browser: renderer"). Read from the scrubbed argv and the executable name only.
private enum RowRole {
    private static let titles = Dictionary(Signatures.all.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })

    static func title(_ c: ClassifiedProcess) -> String {
        guard let id = c.evidence.signatureID, let base = titles[id] else { return c.process.name.isEmpty ? "Unnamed" : c.process.name }
        guard let part = detail(id, c.process) else { return base }
        return "\(base): \(part)"
    }

    private static func detail(_ id: String, _ p: ProcessSnapshot) -> String? {
        switch id {
        case "mcp-official", "mcp-server-named", "mcp-suffix": return mcpName(p.argv)
        case "codex-app-server": return "app server"
        case "codex-node-repl": return "Node REPL"
        case "automation-chrome": return helperKind(p.name)
        default: return nil
        }
    }

    /// `server-filesystem`, `mcp-server-github` and `context7-mcp` (with any scope, path or `@latest`) are "filesystem",
    /// "github" and "context7".
    private static func mcpName(_ argv: [String]) -> String? {
        for word in argv.flatMap({ $0.split(separator: " ") }) {
            guard let name = word.split(separator: "/").last?.split(separator: "@").first.map(String.init) else { continue }
            for prefix in ["mcp-server-", "server-"] where name.hasPrefix(prefix) && name.count > prefix.count {
                return String(name.dropFirst(prefix.count))
            }
            if name.hasSuffix("-mcp"), name.count > 4 { return String(name.dropLast(4)) }
        }
        return nil
    }

    /// "Google Chrome for Testing Helper (Renderer)" is a "renderer"; the browser itself has no extra word.
    private static func helperKind(_ name: String) -> String? {
        guard let open = name.range(of: "Helper (") else { return name.contains("Helper") ? "helper" : nil }
        let rest = name[open.upperBound...]
        return rest.firstIndex(of: ")").map { rest[..<$0].lowercased() }
    }
}

/// "Stop this one…" for a single Maybe. A Maybe that started under `confirmYoungerThanHours` ago asks for its own
/// tick first (BUILD_PLAN §3 rule 9); the confirm sheet follows either way.
struct MaybeStopButton: View {
    let c: ClassifiedProcess
    let now: Date
    @EnvironmentObject private var model: AppModel
    @State private var asking = false

    var body: some View {
        let young = Classifier.requiresYoungConfirmation(c, prefs: model.prefs, now: now)
        Button("Stop This One…") {
            if young { asking = true } else { model.requestStop(single: c, confirmedYoung: false) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(model.phase != .idle)
        .confirmationDialog("Stop \(c.process.name)?", isPresented: $asking, titleVisibility: .visible) {
            Button("Continue") { model.requestStop(single: c, confirmedYoung: true) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("It \(Format.started(seconds: c.process.age(at: now))). Overstay asks twice about anything under \(model.prefs.confirmYoungerThanHours) hours old, because something may still be using it. Stopping cannot be undone.")
        }
    }
}
