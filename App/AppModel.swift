import AppKit
import OverstayCore
import OverstayMac
import SwiftUI

/// The single source of truth (BUILD_PLAN §7): Core makes the groups and the stop plans, the backend reads and signals,
/// the views read this from the environment. The only file with UserDefaults and, with OverstayApp, the only one that
/// opens URLs or apps (safety_greps.sh checks 4b and 8).
@MainActor final class AppModel: ObservableObject {
    enum Tab: Hashable { case groups, activity }

    enum Phase: Equatable {
        case idle
        /// The confirm sheet (or the popover's confirm bar). A `.force` plan is a second, explicit confirmation.
        case confirming(StopPlan)
        /// `finished` is how many outcomes have been reported, in the plan's signalling order (leaf first).
        case running(StopPlan, finished: Int)
        case result(StopOutcome)
    }

    enum MenuBarState: Equatable {
        case scanning
        case quiet
        case leftovers(count: Int, bytes: UInt64)
    }

    /// `LiveBackend.make()`, or the scenario's backend in a DEBUG demo launch (App/Demo.swift).
    let backend: Backend
    /// nil until the first scan has finished (and until the first-run screen has been passed).
    @Published private(set) var scan: ScanResult?
    @Published private(set) var isScanning = false
    /// Persisted as one JSON blob (not in demo mode). Changing the age gate or the never-touch list re-judges the last scan.
    @Published var prefs: Preferences { didSet { prefsChanged(from: oldValue) } }
    /// Default: every group that has a Ghost. A rescan keeps the user's choices and selects groups that are new.
    @Published var selectedGroupIDs: Set<String> = []
    @Published var detailGroupID: String?
    @Published var tab: Tab = .groups
    @Published private(set) var phase: Phase = .idle
    /// The activity log, oldest first (as `Backend.loadLog`); views sort it.
    @Published private(set) var log: [ActivityEntry] = []
    @Published var showPreferences = false
    /// Help > What Overstay Reads: the first-run screen again, as a sheet.
    @Published var showIntro = false
    /// The outcome of the latest stop, kept after the result is dismissed so "Copy my number" still has it.
    @Published private(set) var lastOutcome: StopOutcome?

    var isDemo: Bool { backend.isDemo }

    private static let prefsKey = "overstay.preferences"
    private var raw: RawScan?
    private var knownGroupIDs: Set<String> = []
    private var returnToResult: StopOutcome?
    private var popoverShown = false
    private var watchers: [NSObjectProtocol] = []

    init() {
        #if DEBUG
        let demo = Demo.backend   // non-nil only for a demo launch (App/Demo.swift)
        #else
        let demo: Backend? = nil
        #endif
        self.backend = demo ?? LiveBackend.make()
        self.prefs = demo == nil ? Self.storedPrefs() : Preferences()
        watchWindows()
        if demo == nil { startAutoScan() }
        #if DEBUG
        Demo.start(self)
        #endif
    }

    // MARK: - Derived state

    var menuBar: MenuBarState {
        guard let scan else { return .scanning }
        return scan.ghostCount > 0 ? .leftovers(count: scan.ghostCount, bytes: scan.ghostBytes) : .quiet
    }

    /// Groups with at least one Ghost that are ticked: what "Stop N" stops.
    var selectedGroups: [LeftoverGroup] {
        scan?.groups.filter { $0.ghostCount > 0 && selectedGroupIDs.contains($0.id) } ?? []
    }

    /// Leftovers still to be reported while a stop runs (the scan's Ghost count minus the outcomes so far), else the
    /// scan's totals. What remains to be reported, not a promise of what stopped (docs/MOTION.md §3.2).
    var remainingGhosts: (count: Int, bytes: UInt64) {
        guard let scan else { return (0, 0) }
        guard case let .running(plan, finished) = phase else { return (scan.ghostCount, scan.ghostBytes) }
        let done = plan.targets.prefix(finished)
        let doneBytes = done.reduce(UInt64(0)) { $0 + $1.footprintBytes }
        return (max(0, scan.ghostCount - done.count), scan.ghostBytes - min(scan.ghostBytes, doneBytes))
    }

    /// 1 before and after a stop, shrinking to the unselected share while one runs: the popover ring's `progress`.
    var remainingFraction: Double {
        guard let scan, scan.ghostCount > 0 else { return 1 }
        return Double(remainingGhosts.count) / Double(scan.ghostCount)
    }

    /// The groups whose slabs have settled (docs/MOTION.md §3.2): every target of the group has reported (stopped,
    /// survived, skipped or refused). It says Overstay is done with the group, not that memory is free. Slabs settle as
    /// outcomes arrive, never on a fake schedule.
    var settledGroupIDs: Set<String> {
        guard case let .running(plan, finished) = phase, let scan else { return [] }
        let done = Set(plan.targets.prefix(finished).map(\.id))
        return Set(scan.groups.filter { g in
            let pids = Set(g.processes.map(\.process.pid))
            let mine = plan.targets.filter { pids.contains($0.identity.pid) }
            return !mine.isEmpty && mine.allSatisfy { done.contains($0.id) }
        }.map(\.id))
    }

    /// The group a pid is listed in, by pid and never by name.
    func group(containing pid: Int32) -> LeftoverGroup? {
        scan?.groups.first { g in g.processes.contains { $0.process.pid == pid } }
    }

    /// "~/dev/foo", or "Folder unknown" when the processes had no readable working folder.
    func displayPath(_ group: LeftoverGroup) -> String {
        group.project.map { Scrub.tilde($0.root, home: scan?.home ?? "") } ?? "Folder unknown"
    }

    /// "started 3 days ago", measured from the scan so the text is stable between rescans (and in demo mode).
    func startedText(_ group: LeftoverGroup) -> String? {
        guard let start = group.oldestStart, let now = scan?.scannedAt else { return nil }
        return Format.started(seconds: Int(now.timeIntervalSince(start)))
    }

    // MARK: - Scanning

    /// Reads the process table and re-groups. Nothing is read until the first-run screen has been passed, and not while a
    /// stop is confirmed or runs (a plan is never re-scanned under the user). Safe to call twice at once: the second call returns.
    func rescan() async {
        guard prefs.hasSeenFirstRun else { return }
        switch phase {
        case .confirming, .running: return
        case .idle, .result: await performScan()
        }
    }

    private func performScan() async {
        guard !isScanning else { return }
        isScanning = true
        let fresh = await backend.scan()
        isScanning = false
        apply(fresh)
    }

    private func apply(_ fresh: RawScan) {
        raw = fresh
        let result = Scan.analyze(fresh, prefs: prefs, now: fresh.scannedAt)
        scan = result
        let ghostIDs = Set(result.groups.filter { $0.ghostCount > 0 }.map(\.id))
        selectedGroupIDs = selectedGroupIDs.intersection(ghostIDs).union(ghostIDs.subtracting(knownGroupIDs))
        knownGroupIDs = ghostIDs
        if let id = detailGroupID, !result.groups.contains(where: { $0.id == id }) { detailGroupID = nil }
    }

    /// Every `autoScanSeconds` (never under 15 s), and only while the window or the popover is on screen: there is no
    /// background helper. Also once at launch, which is a no-op until the first-run screen has been passed.
    private func startAutoScan() {
        Task {
            await self.rescan()
            while !Task.isCancelled {
                let every = self.prefs.autoScanSeconds > 0 ? max(15, self.prefs.autoScanSeconds) : 60
                try? await Task.sleep(nanoseconds: UInt64(every) * 1_000_000_000)
                if self.prefs.autoScanSeconds > 0, self.isUIVisible { await self.rescan() }
            }
        }
    }

    /// The main window is visible, or the menu bar popover is the key window. VERIFY on macOS 13/15/26: that the
    /// `MenuBarExtra` window is an `NSPanel` that becomes key when it opens.
    private var isUIVisible: Bool { popoverShown || mainWindowVisible }

    private var mainWindowVisible: Bool {
        NSApp.windows.contains { $0.title == "Overstay" && $0.isVisible && !$0.isMiniaturized }
    }

    /// Opening the popover or the window shows fresh numbers, at most one scan per 5 s.
    private func watchWindows() {
        let center = NotificationCenter.default
        watchers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            let isPanel = note.object is NSPanel
            Task { @MainActor in
                guard let self else { return }
                if isPanel {
                    self.popoverShown = true
                    // A confirmation left in the popover is stale by the next time it opens, unless the main window shows it.
                    if case .confirming = self.phase, !self.mainWindowVisible { self.cancelStop() }
                }
                self.rescanIfStale()
            }
        })
        watchers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
            let isPanel = note.object is NSPanel
            Task { @MainActor in if isPanel { self?.popoverShown = false } }
        })
    }

    private func rescanIfStale() {
        guard !backend.isDemo, prefs.hasSeenFirstRun, !isScanning, phase == .idle else { return }
        if let last = scan?.scannedAt, Date().timeIntervalSince(last) < 5 { return }
        Task { await self.rescan() }
    }

    // MARK: - Stopping

    /// Plans a polite stop of the Ghosts in these groups (Maybes never go in a bulk) and asks for confirmation.
    func requestStop(groupIDs: [String]) { makePlan(.ghosts(groupIDs: groupIDs)) }

    /// One process the user picked, usually a Maybe. `confirmedYoung` is the extra tick for one that started recently.
    func requestStop(single c: ClassifiedProcess, confirmedYoung: Bool) {
        makePlan(.single(pid: c.process.pid, confirmedYoung: confirmedYoung))
    }

    /// What "Stop N" in the popover does: the ticked groups.
    func requestStopSelected() { requestStop(groupIDs: selectedGroups.map(\.id)) }

    private func makePlan(_ selection: StopPlanner.Selection) {
        guard phase == .idle, let scan, let raw else { return }
        let plan = StopPlanner.plan(selection, in: scan, world: Scan.world(raw), prefs: prefs, now: scan.scannedAt,
                                    batchID: UUID().uuidString)
        // Nothing to stop and nothing to explain: do not open an empty sheet. A plan that only skipped things still
        // opens, so the sheet can say why.
        guard !(plan.targets.isEmpty && plan.skipped.isEmpty) else {
            NSSound.beep()
            return
        }
        phase = .confirming(plan)
    }

    /// From the result: a stronger signal for what survived in one group. Needs its own confirmation (`.confirming`).
    func requestForceStop(groupID: String) {
        guard case let .result(outcome) = phase, outcome.mode == .terminate,
              let group = scan?.groups.first(where: { $0.id == groupID }) else { return }
        // Scoped by the group's own pids, never by names: two projects can share an agent and a folder name.
        let pids = Set(group.processes.map(\.process.pid))
        var narrowed = outcome
        narrowed.results = outcome.results.filter { $0.status == .survived && pids.contains($0.target.identity.pid) }
        guard !narrowed.results.isEmpty else {
            NSSound.beep()
            return
        }
        returnToResult = outcome
        phase = .confirming(StopPlanner.forcePlan(from: narrowed, batchID: UUID().uuidString))
    }

    /// Runs the confirmed plan off the main thread. The slabs and the popover ring follow `finished`; when everything has
    /// reported, the app rescans (so the result is on top of fresh groups) and then shows the outcome.
    func confirmStop() async {
        guard case let .confirming(plan) = phase else { return }
        returnToResult = nil
        phase = .running(plan, finished: 0)
        let outcome = await backend.stop(plan, prefs) { [weak self] _ in
            Task { @MainActor in self?.noteFinished() }
        }
        lastOutcome = outcome
        phase = .running(plan, finished: plan.targets.count)
        while isScanning { try? await Task.sleep(nanoseconds: 50_000_000) }
        await performScan()
        reloadLog()
        phase = .result(outcome)
        announce(ShareCardText.headline(ShareCardText.card(stopped: outcome, includeProjectNames: false, isSample: false)))
    }

    private func noteFinished() {
        guard case let .running(plan, n) = phase else { return }
        phase = .running(plan, finished: min(n + 1, plan.targets.count))
    }

    /// Cancel on the confirm sheet. A force confirmation returns to the result it came from.
    func cancelStop() {
        guard case .confirming = phase else { return }
        phase = returnToResult.map { Phase.result($0) } ?? .idle
        returnToResult = nil
    }

    func dismissResult() {
        guard case .result = phase else { return }
        phase = .idle
        returnToResult = nil
    }

    // MARK: - Log, share, links

    func reloadLog() { log = backend.loadLog() }

    func shareCard(stopped: Bool) -> ShareCard {
        let names = prefs.shareIncludesProjectNames
        if stopped, let lastOutcome {
            return ShareCardText.card(stopped: lastOutcome, includeProjectNames: names, isSample: isDemo)
        }
        let found = scan ?? ScanResult(scannedAt: Date(), groups: [], examinedCount: 0)
        return ShareCardText.card(found: found, includeProjectNames: names, isSample: isDemo)
    }

    func openWebsite() { NSWorkspace.shared.open(Links.website) }
    func openReleases() { NSWorkspace.shared.open(Links.releases) }
    func openFalsePositiveIssue() { NSWorkspace.shared.open(Links.falsePositive) }

    /// Shows the activity log in Finder (its folder if the file does not exist yet). Nothing in demo mode: the demo
    /// log lives in memory.
    func revealLog() {
        guard !isDemo else {
            NSSound.beep()
            return
        }
        let folder = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Overstay", isDirectory: true)
        let file = folder.appendingPathComponent(ActivityLog.fileName)
        if !NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: folder.path), !NSWorkspace.shared.open(folder) {
            NSSound.beep()
        }
    }

    /// For testers (Help > Copy Diagnostics): counts, then one block per signature-matching process; no environment, no
    /// full home path (`Diagnostics`).
    func copyDiagnostics() {
        guard let raw else {
            NSSound.beep()
            return
        }
        copyToPasteboard(Diagnostics.text(raw: raw, prefs: prefs, now: raw.scannedAt,
                                          osVersion: ProcessInfo.processInfo.operatingSystemVersionString))
    }

    // MARK: - Preferences

    private static func storedPrefs() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: prefsKey),
              let stored = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        return stored
    }

    private func prefsChanged(from old: Preferences) {
        if !backend.isDemo, let data = try? JSONEncoder().encode(prefs) { UserDefaults.standard.set(data, forKey: Self.prefsKey) }
        if phase == .idle, let raw,
           old.ageGateMinutes != prefs.ageGateMinutes || old.neverTouch != prefs.neverTouch
            || old.confirmYoungerThanHours != prefs.confirmYoungerThanHours {
            apply(raw)   // re-judge what we already read; no new scan needed
        }
        if !old.hasSeenFirstRun, prefs.hasSeenFirstRun, !backend.isDemo { Task { await self.rescan() } }
    }

    /// The spinner has no text of its own, so VoiceOver hears the outcome when a stop finishes.
    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

extension ScanResult {
    /// Nothing, or at least half of what was examined, could not be read: "all quiet" would be a false promise.
    /// ponytail: lives here until Core gets the predicate with a unit test for the threshold (CROSS-AREA).
    var couldNotCheck: Bool { examinedCount == 0 || unreadableCount * 2 >= examinedCount }

    var couldNotCheckText: String {
        let what = examinedCount == 0 ? "any processes" : "\(unreadableCount) of \(examinedCount) processes"
        return "Overstay could not read \(what), so it can't promise nothing is left."
    }
}
