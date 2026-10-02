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

    private func content(_ outcome: StopOutcome) -> some View {
        let stopped = outcome.stoppedCount
        let running = self.survivors(outcome)
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header(outcome)
                if !running.isEmpty { survivorsBox(running, outcome) }
                let rows = self.notes(outcome)
                if !rows.isEmpty {
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
                if stopped > 0 { share }
                buttons(stopped: stopped)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520)
        .frame(minHeight: 300, idealHeight: 520, maxHeight: 640)
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

    /// The card, tilting slightly under the pointer (one of the two places HoverTilt is used), and what to do with it.
    private var share: some View {
        ShareCardView(card: model.shareCard(stopped: true), width: 400)
            .modifier(HoverTilt(max: 4, glare: true))
            .lifted()
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xxs)
    }

    private func buttons(stopped: Int) -> some View {
        HStack(spacing: Space.xs) {
            if stopped > 0 {
                Button(copied ? "Copied" : "Copy My Number") {
                    if Export.copyImage(model.shareCard(stopped: true)) { flashCopied() }
                }
                .buttonStyle(AmberButtonStyle())
                Button("Save as PNG…") { Export.savePNG(model.shareCard(stopped: true)) }
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
        let place = entry.group.map { model.displayPath($0) } ?? first.projectName
        return "\(entry.targets.count) in \(first.agent.displayName)" + (place.map { " · \($0)" } ?? "")
    }

    /// "node ×2, Chrome for Testing ×1": the three most common executables.
    private func kinds(of targets: [StopTarget]) -> String {
        let names = Dictionary(grouping: targets, by: \.name).map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        return names.prefix(3).map { "\($0.name) ×\($0.count)" }.joined(separator: ", ") + (names.count > 3 ? ", and \(names.count - 3) more kinds" : "")
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
