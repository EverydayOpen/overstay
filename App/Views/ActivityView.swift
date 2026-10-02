import OverstayCore
import SwiftUI

/// The activity log (docs/DESIGN.md §6.5): every target of every stop, newest first, days under small-caps headers, a stop
/// under its own line. A stop of five or more targets starts closed (its line says how it went), so a 183-process stop
/// does not bury the days before it. Read-only. The log holds no command lines, no environment and no full paths
/// (BUILD_PLAN §3 rule 8).
struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    /// MainView passes the model's reveal-in-Finder action when it has one (opening Finder lives in AppModel only).
    /// Without it the button is simply not shown.
    var reveal: (() -> Void)? = nil
    /// Stops the reader has opened or closed against their default.
    @State private var flipped: Set<String> = []

    /// One Stop click. `entries` keep the log's own order, which is the order they were stopped in (leaf first).
    private struct Batch: Identifiable {
        let id: String
        let entries: [ActivityEntry]
        var start: Date { entries.map(\.timestamp).min() ?? .distantPast }
        var opensByDefault: Bool { entries.count < 5 }
    }

    private struct Day: Identifiable {
        let id: Date
        let batches: [Batch]
    }

    var body: some View {
        let days = self.days
        VStack(spacing: 0) {
            header
            Divider()
            if days.isEmpty {
                empty
            } else {
                List {
                    ForEach(days) { day in
                        Section {
                            ForEach(day.batches) { batch in
                                if batch.entries.count == 1, let only = batch.entries.first {
                                    EntryRow(entry: only, showsTime: true)
                                } else {
                                    DisclosureGroup(isExpanded: expanded(batch)) {
                                        ForEach(batch.entries) { EntryRow(entry: $0, showsTime: false) }
                                    } label: {
                                        BatchLine(entries: batch.entries, start: batch.start)
                                    }
                                }
                            }
                        } header: {
                            Text(title(of: day.id)).font(.caption.weight(.semibold).smallCaps()).foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { model.reloadLog() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Activity").font(.system(size: 22, weight: .semibold)).tracking(-0.3)
                Text("Every stop is listed here, newest first, including what was skipped. The log is a file on this Mac that Overstay only adds to.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            if let reveal {
                Button("Reveal Log in Finder", action: reveal).buttonStyle(.bordered)
                    .disabled(model.isDemo || model.log.isEmpty)
                    .help(model.isDemo ? "The sample log is not a file" : model.log.isEmpty ? "No log file yet: nothing has been stopped" : "Show the log in Finder")
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.m)
    }

    private var empty: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: "list.bullet.rectangle").font(.system(size: 28)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Nothing stopped yet").font(.system(size: 15, weight: .semibold))
            Text("Every stop Overstay makes will be listed here.").foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Room(strength: 0.5))
        .accessibilityElement(children: .combine)
    }

    /// Days and stops newest first. A stop sits under the day it began.
    private var days: [Day] {
        // A write-ahead line is only shown when no outcome line followed it.
        let finals = Set(model.log.filter { $0.result != .signalled }.map(\.id))
        let shown = model.log.filter { $0.result != .signalled || !finals.contains($0.id) }
        let batches = Dictionary(grouping: shown, by: \.batchID).map { Batch(id: $0.key, entries: $0.value) }
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: batches) { calendar.startOfDay(for: $0.start) }
        return byDay.keys.sorted(by: >).map { day in
            Day(id: day, batches: (byDay[day] ?? []).sorted { $0.start != $1.start ? $0.start > $1.start : $0.id < $1.id })
        }
    }

    private func expanded(_ batch: Batch) -> Binding<Bool> {
        Binding(get: { batch.opensByDefault != flipped.contains(batch.id) },
                set: { open in
                    if open == batch.opensByDefault { flipped.remove(batch.id) } else { flipped.insert(batch.id) }
                })
    }

    private func title(of day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

/// The line a stop sits under: when, how it went, how much it held and where.
private struct BatchLine: View {
    let entries: [ActivityEntry]
    let start: Date

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Text(start.formatted(date: .omitted, time: .shortened))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.s)
            Text(Format.count(entries.count, "process"))
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func count(_ results: [TargetStatus]) -> Int { entries.filter { results.contains($0.result) }.count }

    /// "Stopped 181 · 2 refused by macOS". Findings only, in the log's own words.
    private var summary: String {
        let force = entries.contains { $0.mode == .force }
        var parts: [String] = []
        let stopped = count([.stopped, .forceStopped])
        if stopped > 0 { parts.append("\(force ? "Force stopped" : "Stopped") \(stopped)") }
        let running = count([.survived])
        if running > 0 { parts.append("\(running) still running") }
        let refused = count([.refused, .failed])
        if refused > 0 { parts.append("\(refused) refused by macOS") }
        let aside = count([.alreadyGone, .changedSinceScan, .blocked])
        if aside > 0 { parts.append("\(aside) left alone") }
        return parts.isEmpty ? "Nothing stopped" : parts.joined(separator: " · ")
    }

    /// "9.4 GB held · foo, bar, baz and 2 more": the memory of what stopped, then the most affected places.
    private var detail: String {
        let held = entries.reduce(UInt64(0)) { $0 + ($1.result.wasStopped ? $1.footprintBytes : 0) }
        var tally: [String: Int] = [:]
        for e in entries {
            if let place = e.project ?? (e.agent == .unattributed ? nil : e.agent.displayName) { tally[place, default: 0] += 1 }
        }
        let places = tally.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map { $0.key }
        var parts: [String] = []
        if held > 0 { parts.append("\(Format.bytes(held)) held") }
        if !places.isEmpty {
            parts.append(places.prefix(3).joined(separator: ", ") + (places.count > 3 ? " and \(places.count - 3) more" : ""))
        }
        return parts.joined(separator: " · ")
    }
}

private struct EntryRow: View {
    let entry: ActivityEntry
    /// A stop's line carries the time; a lone entry carries its own.
    let showsTime: Bool
    private static let titles = Dictionary(Signatures.all.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            if showsTime {
                Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.executable.isEmpty ? "Unnamed" : entry.executable).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Text(entry.why).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            Label {
                Text(word)
            } icon: {
                Image(systemName: entry.result.symbol).foregroundStyle(entry.result.tint)
            }
            .font(.system(size: 12))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// "MCP server · foo · 52 MB": what it matched, which project, what it held.
    private var detail: String {
        var parts = [Self.titles[entry.signatureID] ?? entry.signatureID]
        if let project = entry.project { parts.append(project) }
        parts.append(Format.bytes(entry.footprintBytes))
        return parts.joined(separator: " · ")
    }

    private var word: String {
        switch entry.result {
        case .stopped: return "Stopped"
        case .forceStopped: return "Force stopped"
        case .survived: return "Still running"
        case .alreadyGone: return "Already gone"
        case .changedSinceScan: return "Changed, left alone"
        case .blocked: return "Protected, left alone"
        case .refused: return "macOS said no"
        case .failed: return "Failed"
        case .signalled: return "Signal sent, outcome not recorded"
        }
    }
}
