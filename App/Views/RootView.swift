import OverstayCore
import SwiftUI

/// The main window's content (BUILD_PLAN's `MainView`): the first-run screen until it has been passed, then the Groups or
/// Activity tab under one toolbar, and every sheet, one at a time: the Stop flow (confirm, then running), the result,
/// Preferences and the "What Overstay Reads" sheet. Hosting them here means they show on either tab.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var copied = false

    private enum ActiveSheet: Hashable, Identifiable {
        case stop, result, preferences, intro
        var id: Self { self }
    }

    var body: some View {
        Group {
            if model.prefs.hasSeenFirstRun {
                main
            } else {
                FirstRunView()
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .sheet(item: sheet) { which in
            switch which {
            case .stop: StopFlowSheet().environmentObject(model)
            case .result: ResultSheet().environmentObject(model)
            case .preferences: PreferencesSheet().environmentObject(model)
            case .intro: FirstRunView(isSheet: true).environmentObject(model)
            }
        }
    }

    private var main: some View {
        Group {
            switch model.tab {
            case .groups: GroupsView()
            case .activity: ActivityView(reveal: { model.revealLog() })
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $model.tab) {
                    Text("Groups").tag(AppModel.Tab.groups)
                    Text("Activity").tag(AppModel.Tab.activity)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .help("Groups or the activity log")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.isDemo { Tag(text: ShareCardText.sampleWatermark, tint: Brand.amber) }
                Button { Task { await model.rescan() } } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .disabled(model.isScanning || model.phase != .idle)
                    .help("Rescan")
                Button {
                    if Export.copyImage(model.shareCard(stopped: false)) { flashCopied() }
                } label: {
                    Label(copied ? "Copied" : "Copy My Number", systemImage: copied ? "checkmark" : "square.and.arrow.up")
                }
                // No card before the first scan, and none that says "all quiet" when most processes could not be read.
                .disabled(model.scan.map { $0.isQuiet && $0.couldNotCheck } ?? true)
                .help(copied ? "Copied to the clipboard" : "Copy a picture of your number to the clipboard")
                Button { model.showPreferences = true } label: { Label("Preferences", systemImage: "gearshape") }
                    .help("Preferences")
            }
        }
    }

    /// Copying has no visible effect, so the button reads "Copied" for a moment.
    private func flashCopied() {
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }

    /// One sheet at a time. Preferences only while nothing is stopping.
    private var sheet: Binding<ActiveSheet?> {
        Binding(
            get: {
                if model.showIntro { return .intro }
                switch model.phase {
                case .confirming, .running: return .stop
                default: break
                }
                if case .result = model.phase { return .result }
                if model.showPreferences, model.phase == .idle { return .preferences }
                return nil
            },
            // Esc or a click outside. Cancels a confirmation only: a running stop cannot be cancelled.
            set: { _ in
                if model.showIntro {
                    model.showIntro = false
                    return
                }
                switch model.phase {
                case .confirming, .running: model.cancelStop()
                case .result: model.dismissResult()
                case .idle: model.showPreferences = false
                }
            })
    }
}
