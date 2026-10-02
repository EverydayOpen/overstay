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
///     -demoScroll <0...1>       scrolls the main window's widest scrollable area to that fraction (the detail column, the
///                               activity list: what is below the fold), after the entrance animations
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
        /// Idle, then Stop with no confirm sheet and no Stopping sheet over the slabs, a 4 s run, then the result: the
        /// README hero's frames (screens.yml records it).
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
        // `hero` takes the real demo stop, slowed to 4 s, so the rescan after it shows the leftovers gone. The plan is
        // leaf-first, so the slabs settle in the last third of the run. `running` hangs.
        var backend = DemoBackend.make(demo.scenario, seconds: demo.screen == .hero ? 4 : 1.2)
        if demo.screen == .running { backend.stop = { plan, _, progress in await Demo.script(plan, progress, seconds: 1, stopAt: 0.4) } }
        return backend
    }

    /// Once per launch; a share-card run opens nothing (it quits as soon as the PNG is written).
    @MainActor static func openMainWindow(_ show: () -> Void) {
        guard setup != nil, !mainOpened else { return }
        mainOpened = true
        show()
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
        if let fraction = argument("demoScroll").flatMap(Double.init) {
            // Three passes: a lazy List or ScrollView only knows its full height after the first rows have been measured.
            Task { for wait in [3.0, 1.0, 1.0] { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)); scroll(to: fraction) } }
        }
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
            while !mainOpened { try? await Task.sleep(nanoseconds: 50_000_000) }   // the recording starts when the window is up
            try? await Task.sleep(nanoseconds: 2_500_000_000)   // idle frames first
            // The slabs are the shot, and RootView hangs a sheet over them for the confirm step and again while the stop
            // runs. Plan and confirm in one turn, so the confirm sheet is never drawn, and keep the Stopping sheet invisible
            // until the result (which is wanted at the end). The window beneath is the real one: its controls read as
            // disabled and its title bar as inactive, as they do during a real stop.
            model.requestStop(groupIDs: ids)
            let hiding = Task { await hideSheets(while: model) }
            await model.confirmStop()
            await hiding.value
            try? await Task.sleep(nanoseconds: 700_000_000)
            for sheet in NSApp.windows.compactMap(\.attachedSheet) { sheet.alphaValue = 1 }   // in case the result reused the window
        }
    }

    /// Sets any sheet of the app's windows to fully transparent every 20 ms while a stop is confirmed or running.
    /// VERIFY on a Mac that `alphaValue` hides a SwiftUI sheet window and that the next sheet comes up opaque.
    @MainActor private static func hideSheets(while model: AppModel) async {
        func stopping() -> Bool {
            switch model.phase {
            case .confirming, .running: return true
            default: return false
            }
        }
        while stopping() {
            for sheet in NSApp.windows.compactMap(\.attachedSheet) { sheet.alphaValue = 0 }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// The main window's widest scrollable area (the sidebar is narrower), scrolled to `fraction` of its travel from the top.
    /// VERIFY on a Mac that SwiftUI's ScrollView and List are NSScrollViews in the main window.
    @MainActor private static func scroll(to fraction: Double) {
        guard let root = NSApp.windows.first(where: { $0.title == "Overstay" })?.contentView else { return }
        var best: NSScrollView?
        func find(_ view: NSView) {
            if let scroller = view as? NSScrollView, let document = scroller.documentView,
               document.frame.height > scroller.contentView.bounds.height + 1,
               scroller.frame.width > (best?.frame.width ?? 0) { best = scroller }
            view.subviews.forEach(find)
        }
        find(root)
        guard let scroller = best, let document = scroller.documentView else { return }
        let travel = document.frame.height - scroller.contentView.bounds.height
        scroller.contentView.scroll(to: NSPoint(x: 0, y: travel * (document.isFlipped ? fraction : 1 - fraction)))
        scroller.reflectScrolledClipView(scroller.contentView)
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
