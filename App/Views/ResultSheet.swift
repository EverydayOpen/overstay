import OverstayCore
import SwiftUI

/// What a stop did (docs/DESIGN.md §6.5): the headline, what is still running with a per-group Force stop, what was left
/// alone or refused, and the share card. It reads the outcome from `AppModel.phase`; Force stop hands over to the confirm
/// sheet (its own confirmation) and Cancel there comes back here. Nothing here claims memory was freed or that anything can
/// be undone.
struct ResultSheet: View {
    @EnvironmentObject private var model: AppModel
    @State private var copied = false

    private struct Survivors: Identifiable {
        /// The group's id, or "-" for survivors that are in no listed group (no Force stop for those).
        let id: String
        let group: LeftoverGroup?
        let targets: [StopTarget]
    }

    private struct Note: Identifiable {
        let status: TargetStatus
        let text: String
        var id: String { text }
    }

    var body: some View {
        if case let .result(outcome) = model.phase { content(outcome) }
    }

    /// Sized to its content: the page and the buttons when they fit (`ViewThatFits`), and when the page is taller than the
    /// sheet's cap only the page scrolls, with the buttons pinned below it. No fixed height, so no dead space.
    private func content(_ outcome: StopOutcome) -> some View {
        let stopped = outcome.stoppedCount
        let running = self.survivors(outcome)
        let rows = self.notes(outcome)
        let page = VStack(alignment: .leading, spacing: Space.l) {
            header(outcome)
            if !running.isEmpty { survivorsBox(running, outcome) }
            if !rows.isEmpty { notesList(rows) }
            if stopped > 0 { share(width: running.isEmpty ? 472 : 340) }
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        let bar = buttons(stopped: stopped)
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xl)
        return ViewThatFits(in: .vertical) {
            VStack(spacing: 0) {
                page
                bar
            }
            VStack(spacing: 0) {
                ScrollView { page }
                bar
            }
        }
        .frame(width: 520)
        .frame(maxHeight: 640)
        .background(Room())
    }

    // MARK: - Pieces

    private func header(_ outcome: StopOutcome) -> some View {
        let stopped = outcome.stoppedCount
        let verb = outcome.mode == .force ? "Force stopped" : "Stopped"
        return VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(stopped > 0 ? "\(verb) \(stopped). \(Format.bytes(outcome.heldBytes)) was held." : "Nothing was stopped.")
                    .font(.system(size: 22, weight: .semibold)).tracking(-0.3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                if model.isDemo { Tag(text: ShareCardText.sampleWatermark, tint: Brand.amber) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func notesList(_ rows: [Note]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(rows) { note in
                Label {
                    Text(note.text).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: note.status.symbol).foregroundStyle(note.status.tint)
                }
                .font(.system(size: 13))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func survivorsBox(_ survivors: [Survivors], _ outcome: StopOutcome) -> some View {
        let polite = outcome.mode == .terminate
        return VStack(alignment: .leading, spacing: Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Still running").font(.system(size: 13, weight: .semibold))
                Text(polite ? "These ignored the polite signal. Force stop sends a stronger one and gives a process no chance to save or clean up."
                            : "These are still running after the stronger signal. Overstay sends nothing stronger.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(survivors) { entry in
                HStack(alignment: .top, spacing: Space.s) {
                    Image(systemName: TargetStatus.survived.symbol).foregroundStyle(TargetStatus.survived.tint)
                        .frame(width: 18).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(of: entry)).font(.system(size: 13, weight: .semibold))
                        Text(kinds(of: entry.targets)).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Space.xs)
                    if polite, let group = entry.group {
                        Button("Force Stop…") { model.requestForceStop(groupID: group.id) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Force stop \(Format.count(entry.targets.count, "process")) in \(Grouping.title(group))")
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(16)
    }

    /// The card in full (the art is scaled to `width`, never cropped), tilting slightly under the pointer (one of the two
    /// places HoverTilt is used). The padding is the room its lift shadow needs.
    private func share(width: CGFloat) -> some View {
        let card = model.shareCard(stopped: true)
        return ShareCardView(card: card, weights: model.shareWeights(card), width: width)
            .modifier(HoverTilt(max: 4, glare: true))
            .lifted()
            .frame(maxWidth: .infinity)
            .padding(.bottom, Space.xs)
    }

    private func buttons(stopped: Int) -> some View {
        HStack(spacing: Space.xs) {
            if stopped > 0 {
                Button(copied ? "Copied" : "Copy My Number") {
                    let card = model.shareCard(stopped: true)
                    if Export.copyImage(card, weights: model.shareWeights(card)) { flashCopied() }
                }
                .buttonStyle(AmberButtonStyle())
                Button("Save as PNG…") {
                    let card = model.shareCard(stopped: true)
                    Export.savePNG(card, weights: model.shareWeights(card))
                }
                .buttonStyle(.bordered)
            }
            Button("Open the Log") {
                model.reloadLog()
                model.tab = .activity
                model.dismissResult()
            }
            .buttonStyle(.borderless)
            Spacer()
            Button("Done") { model.dismissResult() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
        }
    }

    private func flashCopied() {
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }

    // MARK: - Words

    /// Survivors per group, by pid and never by name. The rescan that ran before this sheet has the survivors back in
    /// their groups; one that is in none still gets a row (without Force stop).
    private func survivors(_ outcome: StopOutcome) -> [Survivors] {
        var order: [String] = []
        var buckets: [String: [StopTarget]] = [:]
        for t in outcome.survivors {
            let id = model.group(containing: t.identity.pid)?.id ?? "-"
            if buckets[id] == nil { order.append(id) }
            buckets[id, default: []].append(t)
        }
        return order.map { id in
            Survivors(id: id, group: model.scan?.groups.first { $0.id == id }, targets: buckets[id] ?? [])
        }
    }

    /// "3 in Claude Code · ~/dev/foo"
    private func title(of entry: Survivors) -> String {
        guard let first = entry.targets.first else { return "" }
        let place = entry.group.flatMap { $0.project == nil ? nil : model.displayPath($0) } ?? first.projectName
        return "\(entry.targets.count) in \(first.agent.displayName)" + (place.map { " · \($0)" } ?? "")
    }

    /// "node ×2, Google Chrome for Testing ×10": the three most common executables, a browser's helper processes counted
    /// under the browser ("... Helper (Renderer)" and "... Helper (GPU)" are not separate kinds to the reader).
    private func kinds(of targets: [StopTarget]) -> String {
        let names = Dictionary(grouping: targets) { $0.name.components(separatedBy: " Helper").first ?? $0.name }
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        return names.prefix(3).map { "\($0.name) ×\($0.count)" }.joined(separator: ", ") + (names.count > 3 ? ", and \(names.count - 3) more" : "")
    }

    /// What did not go to plan, in the fixed words (the popover says the same).
    private func notes(_ o: StopOutcome) -> [Note] {
        func count(_ s: Set<TargetStatus>) -> Int { o.results.filter { s.contains($0.status) }.count }
        var out: [Note] = []
        let refused = count([.refused, .failed])
        if refused > 0 { out.append(Note(status: .refused, text: "macOS did not allow Overstay to stop \(Format.count(refused, "process")).")) }
        let changed = count([.changedSinceScan])
        if changed > 0 { out.append(Note(status: .changedSinceScan, text: "Left alone: \(changed) changed since the scan.")) }
        let blocked = count([.blocked])
        if blocked > 0 {
            out.append(Note(status: .blocked, text: o.results.first { $0.status == .blocked }?.detail ?? "Left alone: \(Format.count(blocked, "process")) protected."))
        }
        if !o.skipped.isEmpty { out.append(Note(status: .blocked, text: PlanLines.skippedText(o.skipped))) }
        let gone = count([.alreadyGone])
        if gone > 0 { out.append(Note(status: .alreadyGone, text: "\(gone) had already exited.")) }
        return out
    }
}
