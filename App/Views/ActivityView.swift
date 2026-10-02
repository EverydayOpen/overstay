import OverstayCore
import SwiftUI

/// The activity log (docs/DESIGN.md §6.5): every target of every stop, newest first, days under small-caps headers.
/// Read-only. The log holds no command lines, no environment and no full paths (BUILD_PLAN §3 rule 8).
struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    /// MainView passes the model's reveal-in-Finder action when it has one (opening Finder lives in AppModel only).
    /// Without it the button is simply not shown.
    var reveal: (() -> Void)? = nil

    private struct Day: Identifiable {
        let id: Date
        let entries: [ActivityEntry]
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
                            ForEach(day.entries) { EntryRow(entry: $0) }
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

    /// Newest first. Lines of one stop share a whole-second timestamp, so ties keep the log's own order, reversed.
    private var days: [Day] {
        // A write-ahead line is only shown when no outcome line followed it.
        let finals = Set(model.log.filter { $0.result != .signalled }.map(\.id))
        let newest = model.log.enumerated().filter { $0.element.result != .signalled || !finals.contains($0.element.id) }.sorted { a, b in
            a.element.timestamp != b.element.timestamp ? a.element.timestamp > b.element.timestamp : a.offset > b.offset
        }.map(\.element)
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: newest) { calendar.startOfDay(for: $0.timestamp) }
        return byDay.keys.sorted(by: >).map { Day(id: $0, entries: byDay[$0] ?? []) }
    }

    private func title(of day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct EntryRow: View {
    let entry: ActivityEntry
    private static let titles = Dictionary(Signatures.all.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
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
