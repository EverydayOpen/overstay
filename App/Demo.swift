#if DEBUG
import AppKit
import OverstayCore
import SwiftUI

/// Screenshots (.github/workflows/screens.yml), DEBUG builds only (BUILD_PLAN §9). A launch argument opens one screen on
/// synthetic data: the scenario's process table is built in Core (`DemoBackend`), so nothing is read from or signalled to
/// the real system and no activity is logged.
///
///     -demoScreen <screen>      or --demo-screen
///     -demo <scenario>          or --demo, or OVERSTAY_DEMO=<scenario>; each screen has a default scenario
///     -demoAppearance light|dark
///     -demoShareOut <png path>  renders the share card with Export and quits (screen: share)
///
/// Names ignore case and hyphens. An unknown name stops the app, so a typo in the workflow fails its capture.
/// AppModel calls `Demo.backend` when it picks its backend and `Demo.start(self)` at the end of init.
enum Demo {
    enum Screen: String, CaseIterable {
        case firstRun
        /// The popover alone, in an ordinary window (the real one only exists while the menu bar item is open).
        case popover
        /// A drawn menu bar strip with the real label (amber badge) above the popover: the hero's first frames.
        case menuBar
        case groups, detail
        /// The confirm sheet.
        case stopSheet
        /// Frozen at 40 percent: the collapse part way.
        case running
        case result
        /// The result with the scenario `refused` (default): "macOS did not allow Overstay to stop ...".
        case edge
        case activity, preferences
        /// The share card at 2x in its own window.
        case share
        /// Idle, then Stop, then a 3 s run, then the result: the README hero's frames (screens.yml records it).
        case hero
    }

    /// nil on a normal launch.
    private static let setup: (screen: Screen, scenario: DemoScenario)? = {
        let name = argument("demoScreen")
        let given = argument("demo") ?? ProcessInfo.processInfo.environment["OVERSTAY_DEMO"]
        guard name != nil || given != nil else { return nil }
        let aliases: [String: Screen] = ["main": .groups, "confirm": .stopSheet]   // BUILD_PLAN §9's names
        let screen = name.map { (n: String) -> Screen in parse(n, "screen", alias: aliases) } ?? .groups
        var scenario = DemoScenario.leftovers
        if screen == .firstRun { scenario = .firstRun }
        if screen == .edge { scenario = .refused }
        if let given { scenario = parse(given, "scenario") }
        return (screen, scenario)
    }()

    /// Non-nil in demo mode: the scenario's backend. `running` and `hero` swap in a scripted stop (below).
    static let backend: Backend? = setup.map { demo in
        // `hero` takes the real demo stop, slowed to 3 s, so the rescan after it shows the leftovers gone. `running` hangs.
        var backend = DemoBackend.make(demo.scenario, seconds: demo.screen == .hero ? 3 : 1.2)
        if demo.screen == .running { backend.stop = { plan, _, progress in await Demo.script(plan, progress, seconds: 1, stopAt: 0.4) } }
        return backend
    }

    /// Once per launch; a share-card run opens nothing (it quits as soon as the PNG is written).
    @MainActor static func openMainWindow(_ open: () -> Void) {
        guard setup != nil, !mainOpened else { return }
        mainOpened = true
        open()
        activateApp()
    }

    @MainActor private static var mainOpened = false

    private static var started = false
    @MainActor private static var windows: [NSWindow] = []

    /// Called by AppModel.init, after the demo backend is in place.
    @MainActor static func start(_ model: AppModel) {
        guard let demo = setup, !started else { return }
        started = true
        if let look = argument("demoAppearance") {
            NSApplication.shared.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua)
        }
        model.prefs.hasSeenFirstRun = demo.screen != .firstRun
        Task { await run(demo.screen, model) }
    }

    @MainActor private static func run(_ screen: Screen, _ model: AppModel) async {
        if screen == .firstRun { return }   // nothing is read before the first-run screen is passed
        await model.rescan()
        let ids = (model.scan?.groups ?? []).filter { $0.ghostCount > 0 }.map(\.id)   // the default selection
        switch screen {
        case .firstRun, .groups: break
        case .detail: model.detailGroupID = model.scan?.groups.first?.id
        case .stopSheet: model.requestStop(groupIDs: ids)
        case .running, .result, .edge:
            model.requestStop(groupIDs: ids)
            await model.confirmStop()   // `running` never returns: its stop hangs at 40 percent
        case .activity:
            model.requestStop(groupIDs: ids)
            await model.confirmStop()
            model.dismissResult()
            model.reloadLog()
            model.tab = .activity
        case .preferences: model.showPreferences = true
        case .popover: present(popover(model))
        case .menuBar: present(MenuBarStage(model: model))
        case .share:
            model.requestStop(groupIDs: ids)
            await model.confirmStop()
            let card = model.shareCard(stopped: true)
            if let path = argument("demoShareOut") {
                if !Export.writePNG(card, to: URL(fileURLWithPath: path)) { fatalError("Could not write the share card") }
                NSApp.terminate(nil)
            }
            model.dismissResult()
            present(ShareCardView(card: card, width: 2 * ShareCardView.size.width))
        case .hero:
            try? await Task.sleep(nanoseconds: 2_500_000_000)   // idle frames first
            model.requestStop(groupIDs: ids)
            try? await Task.sleep(nanoseconds: 1_200_000_000)   // the confirm sheet
            await model.confirmStop()
        }
    }

    /// A stop that reports every target as stopped, evenly over `seconds`, and with `stopAt` below 1 hangs after that
    /// fraction (the `running` capture). The real stop is never involved: this is a Backend closure in demo mode only.
    private static func script(_ plan: StopPlan, _ progress: @Sendable (TargetOutcome) -> Void,
                               seconds: Double, stopAt fraction: Double = 1) async -> StopOutcome {
        let started = Date()
        let reported = Int((Double(plan.targets.count) * fraction).rounded(.down))
        let pause = UInt64(seconds / Double(max(reported, 1)) * 1_000_000_000)
        var results: [TargetOutcome] = []
        for target in plan.targets.prefix(reported) {
            try? await Task.sleep(nanoseconds: pause)
            let outcome = TargetOutcome(target: target, status: plan.mode == .force ? .forceStopped : .stopped)
            results.append(outcome)
            progress(outcome)
        }
        while fraction < 1 && !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000_000) }
        return StopOutcome(batchID: plan.batchID, mode: plan.mode, startedAt: started, finishedAt: Date(),
                           results: results, skipped: plan.skipped)
    }

    // MARK: Windows for the popover screens

    /// The popover as the menu bar window draws it: 360 pt, material, 12 pt corners.
    @MainActor private static func popover(_ model: AppModel) -> some View {
        PopoverView()
            .environmentObject(model)
            .frame(width: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }

    /// A borderless window with a shadow and nothing else, so `screencapture -l` takes just the view.
    @MainActor private static func present(_ view: some View) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentView = host
        window.center()
        window.orderFrontRegardless()
        windows.append(window)
    }

    /// The drawn menu bar (BUILD_PLAN §9: the real menu bar item cannot be captured headlessly, VERIFY). The label is the
    /// app's own, so the badge is the real one; wifi, battery and the clock are decoration.
    private struct MenuBarStage: View {
        @ObservedObject var model: AppModel

        var body: some View {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 14) {
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100")
                    MenuBarLabel().environmentObject(model)
                    Text("9:41").monospacedDigit()
                }
                .font(.system(size: 13))
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .frame(height: 26)
                .background(Color(nsColor: .windowBackgroundColor))
                Demo.popover(model).padding(.trailing, 10)
            }
            .frame(width: 480)
        }
    }

    // MARK: Arguments

    /// The value after `-name` or `--kebab-name` (`demoScreen` is also `--demo-screen`), never a stored setting.
    private static func argument(_ name: String) -> String? {
        let kebab = name.map { $0.isUppercase ? "-" + $0.lowercased() : String($0) }.joined()
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(where: { $0 == "-" + name || $0 == "--" + kebab }), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    private static func parse<T: CaseIterable & RawRepresentable>(_ name: String, _ what: String, alias: [String: T] = [:]) -> T
    where T.RawValue == String {
        func key(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "-", with: "") }
        guard let hit = alias[key(name)] ?? T.allCases.first(where: { key($0.rawValue) == key(name) }) else {
            fatalError("Unknown demo \(what) \(name)")
        }
        return hit
    }
}

/// A MenuBarExtra-first app presents no window at launch by itself (VERIFY: the first capture run had none within 30 s), and
/// every capture but the share card needs the main one. Applied to the menu bar label, which is alive from launch.
struct DemoLaunch: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear { Demo.openMainWindow { openWindow(id: "main") } }
    }
}
#endif
