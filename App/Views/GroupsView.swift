import OverstayCore
import SwiftUI

/// The Groups tab (docs/DESIGN.md §6.5): the sidebar lists the groups, the detail column is the overview (totals, the
/// weight bar, Maybes) or one group's detail. The sheets, the toolbar and the tab switch belong to RootView.
struct GroupsView: View {
    @EnvironmentObject private var model: AppModel
    private static let overviewTag = "overview"

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 380)
        } detail: {
            detail.safeAreaInset(edge: .bottom, spacing: 0) {
                if let scan = model.scan, !scan.isQuiet { StopBar(scan: scan) }
            }
        }
    }

    private var selection: Binding<String?> {
        Binding(get: { model.detailGroupID ?? Self.overviewTag },
                set: { model.detailGroupID = ($0 == nil || $0 == Self.overviewTag) ? nil : $0 })
    }

    private var sidebar: some View {
        List(selection: selection) {
            Label("Overview", systemImage: "square.grid.2x2").tag(Self.overviewTag)
            if let scan = model.scan, !scan.groups.isEmpty {
                Section("Groups") {
                    ForEach(scan.groups) { group in
                        SidebarRow(group: group, now: scan.scannedAt, home: scan.home).tag(group.id)
                    }
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let scan = model.scan {
            if scan.isQuiet {
                QuietState(scan: scan)
            } else if let id = model.detailGroupID, let group = scan.groups.first(where: { $0.id == id }) {
                GroupDetailView(group: group, now: scan.scannedAt, home: scan.home)
            } else {
                Overview(scan: scan)
            }
        } else {
            ProgressView("Looking for leftovers…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Room(strength: 0.5))
        }
    }
}

// MARK: - Sidebar

private struct SidebarRow: View {
    let group: LeftoverGroup
    let now: Date
    let home: String
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let title = Grouping.title(group)
        let hasGhosts = group.ghostCount > 0
        HStack(alignment: .top, spacing: Space.xs) {
            if hasGhosts {
                Toggle("Select \(title) in \(projectText)", isOn: checked)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            } else {
                Color.clear.frame(width: 16, height: 16)   // Maybe-only groups have nothing to select; keeps the columns aligned
            }
            GroupGlyph(symbol: group.agent.symbol)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: Space.xs)
                    Text("\(hasGhosts ? group.ghostCount : group.maybeCount) · \(Format.bytes(hasGhosts ? group.ghostBytes : group.totalBytes))")
                        .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(projectText).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    if hasGhosts { Tag(text: "\(group.ghostCount) \(Classification.ghost.word)", tint: Classification.ghost.tint) }
                    if group.maybeCount > 0 { Tag(text: "\(group.maybeCount) \(Classification.maybe.word)", tint: Classification.maybe.tint) }
                }
                if let start = group.oldestStart {
                    Text(Format.started(seconds: Int(now.timeIntervalSince(start)))).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 4)
    }

    private var projectText: String {
        group.project.map { Scrub.tilde($0.root, home: home) } ?? "Folder unknown"
    }

    private var checked: Binding<Bool> {
        Binding(get: { model.selectedGroupIDs.contains(group.id) },
                set: { on in
                    if on { model.selectedGroupIDs.insert(group.id) } else { model.selectedGroupIDs.remove(group.id) }
                })
    }
}

/// A symbol in a neutral recessed squircle: the agent mark (SF Symbols only, never vendor logos).
struct GroupGlyph: View {
    let symbol: String
    var size: CGFloat = 24
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(shape.fill(Color.primary.opacity(0.06)))
            .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 1 : 0.10), lineWidth: contrast == .increased ? 1 : 0.5))
            .accessibilityHidden(true)
    }
}

/// Turns a row or card down into place from its top edge, once. Callers flip `shown` inside `withAnimation`.
/// Reduce Motion keeps only the fade. VERIFY the sign of the angle on a Mac (the top edge should start away from the viewer).
struct FlipIn: ViewModifier {
    var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(shown || reduceMotion ? 0 : 70), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
            .opacity(shown ? 1 : 0)
    }
}

// MARK: - Overview

private struct Overview: View {
    let scan: ScanResult
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var barShown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                stats
                if !barGroups.isEmpty { weightBar }
                maybes
                if scan.unreadableCount > 0 {
                    Text("Nothing could be read for \(Format.count(scan.unreadableCount, "process")). Overstay leaves what it can't read alone.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Room())
        .onAppear {
            withAnimation(Motion.spring(reduceMotion)) { barShown = true }
        }
    }

    private var barGroups: [LeftoverGroup] { scan.groups.filter { $0.ghostCount > 0 } }

    /// While a stop runs, the headline counts down with the outcomes that have arrived (MOTION §3.2): what remains to be
    /// reported, not a promise of what stopped. The result sheet shows the real outcome.
    private var remaining: (count: Int, bytes: UInt64) {
        guard case let .running(plan, finished) = model.phase else { return (scan.ghostCount, scan.ghostBytes) }
        let done = plan.targets.prefix(finished)
        let doneBytes = done.reduce(UInt64(0)) { $0 + $1.footprintBytes }
        return (max(0, scan.ghostCount - done.count), scan.ghostBytes - min(scan.ghostBytes, doneBytes))
    }

    @ViewBuilder private var stats: some View {
        if scan.ghostCount == 0 {
            noLeftovers
        } else {
            leftoverStats
        }
    }

    /// Only Maybes: the zeros and the Ghost sentence would say the opposite of what is listed below.
    private var noLeftovers: some View {
        let n = scan.maybeCount
        return VStack(alignment: .leading, spacing: Space.xxs) {
            Text("Nothing clearly left behind.").font(.system(size: 22, weight: .semibold)).tracking(-0.3)
            Text("\(Format.count(n, "process")) \(n == 1 ? "might be a leftover" : "might be leftovers"). Review \(n == 1 ? "it" : "them") below; Overstay never stops Maybes in bulk.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var leftoverStats: some View {
        let left = remaining
        let held = Format.bytes(left.bytes).split(separator: " ", maxSplits: 1).map(String.init)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.m) {
                StageStat(label: "Leftover", value: "\(left.count)", size: 44)
                Divider().frame(height: 52)
                StageStat(label: "Held", value: held.first ?? "0", unit: held.count > 1 ? held[1] : nil)
                Divider().frame(height: 52)
                StageStat(label: "Groups", value: "\(barGroups.count)")
            }
            .animation(Motion.standard(reduceMotion), value: left.count)
            Text("These look like leftovers: their parent is gone and no live session is using their project.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var weightBar: some View {
        WeightBar(groups: scan.groups, selected: $model.selectedGroupIDs, settled: model.settledGroupIDs)
            .padding(12)
            .surface(18)
            .modifier(FlipIn(shown: barShown))
            .animation(Motion.spring(reduceMotion), value: barGroups.map(\.id))
    }

    @ViewBuilder private var maybes: some View {
        let items = scan.groups.flatMap(\.maybes)
        if !items.isEmpty {
            MaybeSection(items: items, home: scan.home, now: scan.scannedAt, startOpen: scan.ghostCount == 0, showsProject: true)
        }
    }
}

/// A small-caps label over a big rounded number. One VoiceOver element.
private struct StageStat: View {
    let label: String
    let value: String
    var unit: String? = nil
    var size: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold).smallCaps()).foregroundStyle(.secondary)   // VERIFY small caps with SF
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                if let unit { Text(unit).font(.callout.weight(.medium)).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "All quiet." Green only here. Nothing in it moves. When most processes could not be read it says so instead of
/// promising anything (`couldNotCheck`), with a neutral glyph.
private struct QuietState: View {
    let scan: ScanResult
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let unsure = scan.couldNotCheck
        VStack(spacing: Space.s) {
            Image(systemName: unsure ? "questionmark.circle" : "checkmark.circle.fill").font(.system(size: 44))
                .foregroundStyle(unsure ? Color.secondary : Color.green).accessibilityHidden(true)
            Text(unsure ? "Couldn't check." : "All quiet. Nothing left behind.").font(.system(size: 22, weight: .semibold))
            if unsure {
                Text(scan.couldNotCheckText).foregroundStyle(.secondary)
            } else {
                Text("Checked \(Format.count(scan.examinedCount, "process"))").foregroundStyle(.secondary)
                if scan.unreadableCount > 0 {
                    Text("Nothing could be read for \(Format.count(scan.unreadableCount, "process")).")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: Space.xs) {
                Button("Rescan") { Task { await model.rescan() } }
                    .disabled(model.isScanning)
                if unsure { CopyButton(title: "Copy Diagnostics") { model.copyDiagnostics() } }
            }
            .buttonStyle(.bordered)
            .padding(.top, Space.xxs)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Room(strength: 0.5))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Bottom bar

private struct StopBar: View {
    let scan: ScanResult
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let ghostGroups = scan.groups.filter { $0.ghostCount > 0 }
        let chosen = ghostGroups.filter { model.selectedGroupIDs.contains($0.id) }
        let count = chosen.reduce(0) { $0 + $1.ghostCount }
        let bytes = chosen.reduce(UInt64(0)) { $0 + $1.ghostBytes }
        let idle = model.phase == .idle
        let all = !ghostGroups.isEmpty && chosen.count == ghostGroups.count
        HStack(spacing: Space.s) {
            Button(all ? "Select None" : "Select All Leftovers") {
                model.selectedGroupIDs = all ? [] : Set(ghostGroups.map(\.id))
            }
            .buttonStyle(.borderless)
            .disabled(ghostGroups.isEmpty || !idle)
            Button("Rescan") { Task { await model.rescan() } }
                .buttonStyle(.borderless)
                .disabled(model.isScanning || !idle)
            if model.isScanning { ProgressView().controlSize(.small) }
            Spacer(minLength: Space.s)
            if count > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Format.count(chosen.count, "group")) selected")
                    Text("\(Format.bytes(bytes)) held")
                }
                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                .accessibilityElement(children: .combine)
            }
            Button(count > 0 ? "Stop \(count)" : "Stop") { model.requestStop(groupIDs: chosen.map(\.id)) }
                .buttonStyle(AmberButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(count == 0 || !idle)
                .accessibilityLabel(count > 0 ? "Stop \(Format.count(count, "leftover process"))" : "Stop")
        }
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.m)
        .barSurface()
        .padding([.horizontal, .bottom], Space.l)
    }
}

// MARK: - The Stop flow sheet

/// What will stop, said plainly, then progress. Nothing here says undo, safe or freed (BUILD_PLAN §3 rule 13):
/// processes cannot be brought back, the polite signal goes first, and a forced stop is its own explicit step.
struct StopFlowSheet: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.phase {
        case .confirming(let plan): ConfirmPane(plan: plan)
        case .running(let plan, let finished): RunningPane(plan: plan, finished: finished)
        default: EmptyView()
        }
    }
}

/// What a plan will stop, per group: "61 in Claude Code · ~/dev/foo" over "node ×58, Chrome for Testing ×3". The confirm
/// sheet shows five, the popover three, both with "and N more groups" so nothing ticked is out of sight.
struct PlanLines: View {
    let plan: StopPlan
    var limit = 5
    @EnvironmentObject private var model: AppModel

    private struct Line: Identifiable {
        let id: String
        let count: Int
        let title: String
        let detail: String
    }

    var body: some View {
        let lines = self.lines
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(lines.prefix(limit)) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                    Text(line.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if lines.count > limit {
                Text("and \(Format.count(lines.count - limit, "more group"))").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    /// "Left out: node (protected), and 2 more." for what the user ticked and the plan refused.
    static func skippedText(_ skipped: [SkippedTarget]) -> String {
        let shown = skipped.prefix(3).map { "\($0.name) (\($0.reason))" }.joined(separator: ", ")
        let more = skipped.count > 3 ? ", and \(skipped.count - 3) more" : ""
        return "Left out: \(shown)\(more)."
    }

    /// One line per group, keyed by the group's id (two projects can share an agent and a folder name); only a pid that
    /// is in no listed group falls back to agent and folder name.
    private var lines: [Line] {
        var order: [String] = []
        var buckets: [String: [StopTarget]] = [:]
        for t in plan.targets {
            let key = model.group(containing: t.identity.pid)?.id ?? "\(t.agent.rawValue)|\(t.projectName ?? "")"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(t)
        }
        let scan = model.scan
        let out: [Line] = order.compactMap { key in
            guard let ts = buckets[key], let first = ts.first else { return nil }
            let project = model.group(containing: first.identity.pid)?.project
            let place = project.map { Scrub.tilde($0.root, home: scan?.home ?? "") } ?? first.projectName
            let names = Dictionary(grouping: ts, by: \.name).map { (name: $0.key, count: $0.value.count) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            let shown = names.prefix(3).map { "\($0.name) ×\($0.count)" }.joined(separator: ", ")
            let more = names.count > 3 ? ", and \(names.count - 3) more kinds" : ""
            return Line(id: key, count: ts.count,
                        title: "\(ts.count) in \(first.agent.displayName)" + (place.map { " · \($0)" } ?? ""),
                        detail: shown + more)
        }
        return out.sorted { $0.count != $1.count ? $0.count > $1.count : $0.title < $1.title }
    }
}

private struct ConfirmPane: View {
    let plan: StopPlan
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let force = plan.mode == .force
        let single = plan.targets.count == 1 && plan.targets[0].approvedTier == .maybe
        let n = plan.targets.count
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(n == 0 ? "Nothing to stop" : force ? "Force stop \(Format.count(n, "process"))?" : "Stop \(Format.count(n, "process"))?")
                    .font(.system(size: 22, weight: .semibold)).tracking(-0.3)
                if n > 0 { Text("\(Format.bytes(plan.totalFootprintBytes)) held by \(n == 1 ? "it" : "them")").foregroundStyle(.secondary) }
            }
            if n == 0 {
                Text("Nothing in this selection can be stopped.").foregroundStyle(.secondary)
            } else {
                PlanLines(plan: plan)
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surface(16)
            }
            if single, let t = plan.targets.first {
                Text("Overstay is less sure about this one: \(t.why)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if !plan.skipped.isEmpty {
                Text(PlanLines.skippedText(plan.skipped)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if n > 0 {
                Text(force ? "Stronger signal · only what survived · waits up to \(Int(plan.graceSeconds)) s"
                           : "Polite signal first · leaf first · waits up to \(Int(plan.graceSeconds)) s")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    if force {
                        Text("These ignored the polite signal. A forced stop gives a process no chance to save or clean up.")
                    }
                    Text("Only processes are touched, never files. This cannot be undone. Anything unsaved inside these processes is lost.")
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelStop() }.keyboardShortcut(.cancelAction)
                Button(force ? "Force Stop \(n)" : "Stop \(n)") { Task { await model.confirmStop() } }
                    .buttonStyle(AmberButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(n == 0)
            }
        }
        .padding(Space.xl)
        .frame(width: 460)
    }
}

private struct RunningPane: View {
    let plan: StopPlan
    let finished: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let total = plan.targets.count
        let done = min(finished, total)
        VStack(alignment: .leading, spacing: Space.m) {
            Text(plan.mode == .force ? "Force stopping" : "Stopping")
                .font(.system(size: 22, weight: .semibold)).tracking(-0.3)
            ProgressView(value: Double(done), total: Double(max(total, 1)))
            Text("\(done) of \(total)")
                .font(.system(.body, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                .animation(Motion.standard(reduceMotion), value: done)
            Text("Leaf first. Overstay waits up to \(Int(plan.graceSeconds)) s after the signal, then reports anything still running.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(Space.xl)
        .frame(width: 460)
        .interactiveDismissDisabled()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(plan.mode == .force ? "Force stopping" : "Stopping")
        .accessibilityValue("\(done) of \(total)")
    }
}
