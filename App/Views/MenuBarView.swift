import AppKit
import OverstayCore
import SwiftUI

/// The menu bar item: the template glyph, or the amber badge with the count while Ghosts exist (docs/DESIGN.md §6.4). It
/// never animates (docs/MOTION.md §3.6): the badge appears and disappears with the scan result, like system status items.
struct MenuBarLabel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.menuBar {
        case .leftovers(let count, _):
            if MenuBarIcon.colorBadge {
                Image(nsImage: MenuBarIcon.badge(count: count))
                    .renderingMode(.original)
                    .accessibilityLabel("Overstay, \(Format.count(count, "leftover process"))")
            } else {
                HStack(spacing: 3) {
                    Image(nsImage: MenuBarIcon.glyph)
                    Text("\(count)").monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Overstay, \(Format.count(count, "leftover process"))")
            }
        case .quiet, .scanning:
            Image(nsImage: MenuBarIcon.glyph)
                .accessibilityLabel("Overstay")
        }
    }
}

/// The window-style `MenuBarExtra` content (docs/DESIGN.md §6.5), 360pt wide. It can run the whole stop on its own: Stop,
/// an inline confirmation (the same words as the confirm sheet), the ring and the count shrinking, then the result line.
/// Survivors, Force stop, the share card and the details live in the main window.
struct PopoverView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    private enum Mode: Equatable { case intro, loading, quiet, unsure, maybes, leftovers, confirming, running, result }

    private var mode: Mode {
        if !model.prefs.hasSeenFirstRun { return .intro }
        switch model.phase {
        case .confirming: return .confirming
        case .running: return .running
        case .result: return .result
        case .idle: break
        }
        guard let scan = model.scan else { return .loading }
        if scan.ghostCount > 0 { return .leftovers }
        return scan.isQuiet ? (scan.couldNotCheck ? .unsure : .quiet) : .maybes
    }

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .intro: intro
            case .loading: loading
            case .quiet: quiet("All quiet. Nothing left behind.", checked)
            case .unsure: quiet("Couldn't check.", model.scan?.couldNotCheckText ?? "", symbol: "questionmark.circle", tint: .secondary)
            case .maybes:
                let n = model.scan?.maybeCount ?? 0
                quiet("Nothing clearly left behind.",
                      "\(Format.count(n, "process")) \(n == 1 ? "might be a leftover" : "might be leftovers"). Review \(n == 1 ? "it" : "them") in Overstay.",
                      symbol: "magnifyingglass.circle", tint: .secondary)
            case .leftovers: leftovers
            case .confirming: if case let .confirming(plan) = model.phase { confirming(plan) }
            case .running: running
            case .result: if case let .result(outcome) = model.phase { result(outcome) }
            }
        }
        .frame(width: 360)
        .animation(Motion.standard(reduceMotion), value: mode)
    }

    // MARK: - States

    private var intro: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "list.bullet.rectangle").font(.system(size: 28)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Overstay hasn't looked yet.").font(.system(size: 15, weight: .semibold))
            Text("Open it once to see what it reads. Nothing is scanned before that.")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open Overstay") { openMain() }
                .buttonStyle(AmberButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .overlay(alignment: .bottomTrailing) { quitButton.padding(Space.s) }
    }

    private var loading: some View {
        VStack(spacing: Space.xs) {
            ProgressView().controlSize(.small)
            Text("Looking for leftovers…").font(.system(size: 12)).foregroundStyle(.secondary)
            links
        }
        .padding(.top, Space.l)
        .frame(maxWidth: .infinity)
    }

    /// All quiet: green only here, a still check, no amber anywhere. The check bounces once on macOS 14+ (Compat), not under
    /// Reduce Motion. The other quiet-looking states pass a neutral glyph and tint, so they never read as a promise.
    private func quiet(_ title: String, _ detail: String, symbol: String = "checkmark.circle.fill", tint: Color = .green) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: Space.xxs) {
                Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(tint)
                    .bounce(on: reduceMotion ? false : arrived)
                    .accessibilityHidden(true)
                    .padding(.bottom, Space.xxs)
                Text(title).font(.system(size: 15, weight: .semibold))
                if model.isDemo { Tag(text: ShareCardText.sampleWatermark, tint: Brand.amber) }
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Space.l).padding(.bottom, Space.m).padding(.horizontal, Space.m)
            .accessibilityElement(children: .combine)
            links
        }
        .onAppear { arrived = true }
    }

    private var leftovers: some View {
        let scan = model.scan
        let groups = (scan?.groups ?? []).filter { $0.ghostCount > 0 }
        return VStack(spacing: Space.s) {
            header(count: scan?.ghostCount ?? 0, bytes: scan?.ghostBytes ?? 0, groups: groups, stopping: false)
            VStack(spacing: 0) {
                ForEach(Array(groups.prefix(3).enumerated()), id: \.element.id) { i, group in
                    if i > 0 { Divider().padding(.leading, 52) }
                    row(group)
                }
            }
            .surface(16)
            .padding(.horizontal, Space.s)
            if groups.count > 3 {
                Text("and \(Format.count(groups.count - 3, "more group"))").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            actionBar
        }
        .padding(.top, Space.m)
    }

    private func confirming(_ plan: StopPlan) -> some View {
        let force = plan.mode == .force
        let n = plan.targets.count
        let groups = (model.scan?.groups ?? []).filter { $0.ghostCount > 0 }
        return VStack(spacing: Space.s) {
            header(count: model.scan?.ghostCount ?? 0, bytes: model.scan?.ghostBytes ?? 0, groups: groups, stopping: false)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(n == 0 ? "Nothing to stop" : force ? "Force stop \(Format.count(n, "process"))?" : "Stop \(Format.count(n, "process"))?")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                // What will be stopped, the same lines as the confirm sheet: groups past the third are counted, not hidden.
                if n > 0 { PlanLines(plan: plan, limit: 3) }
                if !plan.skipped.isEmpty { Text(PlanLines.skippedText(plan.skipped)) }
                if n > 0 {
                    if force { Text("These ignored the polite signal. A forced stop gives a process no chance to save or clean up.") }
                    Text("Only processes are touched, never files. This cannot be undone. Anything unsaved inside these processes is lost.")
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
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(16)
            .padding(.horizontal, Space.s)
            .padding(.bottom, Space.s)
        }
        .padding(.top, Space.m)
    }

    /// The ring shrinks and the count falls as outcomes arrive; the sentence replaces the buttons.
    private var running: some View {
        let groups = (model.scan?.groups ?? []).filter { $0.ghostCount > 0 }
        var done = 0, total = 0
        if case let .running(plan, finished) = model.phase { (done, total) = (min(finished, plan.targets.count), plan.targets.count) }
        return VStack(spacing: Space.s) {
            header(count: model.remainingGhosts.count, bytes: model.remainingGhosts.bytes, groups: groups, stopping: true)
            VStack(alignment: .leading, spacing: Space.xs) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("Stopping… \(done) of \(total)")
                    .font(.system(size: 12, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(Motion.standard(reduceMotion), value: done)
            }
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.m)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stopping")
            .accessibilityValue("\(done) of \(total)")
        }
        .padding(.top, Space.m)
    }

    private func result(_ outcome: StopOutcome) -> some View {
        let stopped = outcome.stoppedCount
        let verb = outcome.mode == .force ? "Force stopped" : "Stopped"
        return VStack(spacing: Space.s) {
            VStack(spacing: Space.xxs) {
                Image(systemName: stopped > 0 ? "checkmark.circle.fill" : "minus.circle").font(.system(size: 36))
                    .foregroundStyle(stopped > 0 ? Color.green : Color.secondary)
                    .accessibilityHidden(true)
                    .padding(.bottom, Space.xxs)
                Text(stopped > 0 ? "\(verb) \(stopped). \(Format.bytes(outcome.heldBytes)) was held." : "Nothing was stopped.")
                    .font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.center)
                ForEach(notes(outcome), id: \.self) { line in
                    Text(line).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            HStack {
                Button("Open Overstay") { openMain() }.buttonStyle(.borderless).keyboardShortcut("o")
                Spacer()
                Button("Done") { model.dismissResult() }
                    .buttonStyle(AmberButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Space.m)
        }
        .padding(.top, Space.l)
        .padding(.bottom, Space.m)
    }

    /// What did not go to plan, in the fixed words (BUILD_PLAN §8).
    private func notes(_ o: StopOutcome) -> [String] {
        func count(_ s: Set<TargetStatus>) -> Int { o.results.filter { s.contains($0.status) }.count }
        var lines: [String] = []
        let survived = count([.survived])
        if survived > 0 {
            let verb = survived == 1 ? "1 is" : "\(survived) are"
            // Force stop exists only after a polite stop, and only for survivors that sit in a listed group.
            let tail = o.mode == .force ? "after the stronger signal. Overstay sends nothing stronger."
                : o.survivors.contains { model.group(containing: $0.identity.pid) != nil } ? "Force stop is in the main window." : ""
            lines.append(("\(verb) still running" + (o.mode == .force ? " " : ". ") + tail).trimmingCharacters(in: .whitespaces))
        }
        let refused = count([.refused, .failed])
        if refused > 0 { lines.append("macOS did not allow Overstay to stop \(Format.count(refused, "process")).") }
        let changed = count([.changedSinceScan])
        if changed > 0 { lines.append("Left alone: \(changed) changed since the scan.") }
        if let blocked = o.results.first(where: { $0.status == .blocked }) {
            lines.append(blocked.detail ?? "Left alone: \(Format.count(count([.blocked]), "process")) protected.")
        }
        return lines
    }

    // MARK: - Pieces

    /// The ring beside the total: one VoiceOver element, and while a stop runs it is not announced on every change.
    private func header(count: Int, bytes: UInt64, groups: [LeftoverGroup], stopping: Bool) -> some View {
        HStack(spacing: Space.s) {
            OrbitRing(groups: groups, progress: stopping ? model.remainingFraction : 1, size: 56)
                .animation(Motion.standard(reduceMotion), value: model.remainingFraction)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(count)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Motion.standard(reduceMotion), value: count)
                Text("leftover · \(Format.bytes(bytes))").font(.system(size: 15)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if model.isDemo { Tag(text: ShareCardText.sampleWatermark, tint: Brand.amber) }
        }
        .padding(.horizontal, Space.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stopping ? "Stopping leftover processes" : "\(Format.count(count, "leftover process")) holding \(Format.bytes(bytes))")
    }

    /// A ticked group is part of "Stop N". One tap toggles; the checkmark is a symbol, never colour alone.
    private func row(_ group: LeftoverGroup) -> some View {
        let on = model.selectedGroupIDs.contains(group.id)
        let title = Grouping.title(group)
        return Button {
            if model.selectedGroupIDs.remove(group.id) == nil { model.selectedGroupIDs.insert(group.id) }
        } label: {
            HStack(alignment: .top, spacing: Space.xs) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 15))
                    .foregroundStyle(on ? Brand.amberInk : Color.secondary)
                    .frame(width: 18, height: 22)
                Image(systemName: group.agent.symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .well(.secondary, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(model.displayPath(group)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: Space.xs)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(group.ghostCount) · \(Format.bytes(group.ghostBytes))")
                        .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                    if let started = model.startedText(group) {
                        Text(started).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, Space.s).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(model.displayPath(group)), \(Format.count(group.ghostCount, "process")), \(Format.bytes(group.ghostBytes))")
        .accessibilityValue(on ? "selected" : "not selected")
        .accessibilityHint("Includes or leaves out this group when you stop")
    }

    /// Open, Quit and the one prominent button, on the controls layer.
    private var actionBar: some View {
        let count = model.selectedGroups.reduce(0) { $0 + $1.ghostCount }
        return HStack(spacing: Space.s) {
            Button("Open Overstay") { openMain() }.buttonStyle(.borderless).keyboardShortcut("o")
            quitButton
            Spacer(minLength: Space.xs)
            Button(count > 0 ? "Stop \(count)" : "Stop") { model.requestStopSelected() }
                .buttonStyle(AmberButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(count == 0)
                .accessibilityLabel(count > 0 ? "Stop \(Format.count(count, "leftover process"))" : "Stop")
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
        .barSurface()
        .padding([.horizontal, .bottom], Space.s)
    }

    private var links: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("Open Overstay") { openMain() }.keyboardShortcut("o")
                Spacer()
                quitButton
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
        }
    }

    private var quitButton: some View {
        Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless).keyboardShortcut("q")
    }

    private var checked: String {
        guard let scan = model.scan else { return "" }
        var count = "Checked \(Format.count(scan.examinedCount, "process"))"
        if scan.unreadableCount > 0 { count += " · \(scan.unreadableCount) could not be read" }
        if model.isDemo { return count }
        let ago = Format.age(seconds: Int(Date().timeIntervalSince(scan.scannedAt)))
        return count + " · " + (ago == "just now" ? ago : "\(ago) ago")
    }

    private func openMain() {
        openWindow(id: "main")
        activateApp()
    }
}
