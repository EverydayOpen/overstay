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
        let ghosts = group.ghosts
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
        .background(Room())
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
        var parts = [group.project.map { Scrub.tilde($0.root, home: home) } ?? "Folder unknown"]
        if group.ghostCount > 0 { parts += ["\(group.ghostCount) leftover", Format.bytes(group.ghostBytes)] }
        if group.maybeCount > 0 { parts.append("\(group.maybeCount) Maybe") }
        if let start = group.oldestStart { parts.append(Format.started(seconds: Int(now.timeIntervalSince(start)))) }
        return parts.joined(separator: " · ")
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
                Text(c.process.name.isEmpty ? "Unnamed" : c.process.name)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: Space.xs)
                Text(Format.bytes(c.process.footprintBytes))
                    .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                Tag(text: c.tier.word, tint: c.tier.tint)
            }
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
            field("Running", "pid \(c.process.pid) · \(Format.started(seconds: c.process.age(at: now)))")
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
