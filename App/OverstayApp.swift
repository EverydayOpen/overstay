import AppKit
import SwiftUI

/// A regular app (Dock icon) with a window-style menu bar popover and one main window (BUILD_PLAN §1). Closing the window
/// does not quit; Quit is in the popover and the app menu. There is no login item and no background helper.
@main
struct OverstayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(model)
        } label: {
            MenuBarLabel().environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Window("Overstay", id: "main") {
            RootView().environmentObject(model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 660)
        .commands { OverstayCommands(model: model) }

        Window("About Overstay", id: "about") {
            AboutView().environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}

/// Menus. The Edit menu stays whole (never replace `.pasteboard` or `.textEditing`: tools/repo_checks.sh). Preferences is a
/// sheet in the main window, not a Settings scene, so the commands open the window first.
@MainActor private struct OverstayCommands: Commands {
    @ObservedObject var model: AppModel
    // VERIFY on macOS 13: the environment reaches Commands, so openWindow works from a menu item.
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .appInfo) {
            Button("About Overstay") { show("about") }
            Button("Check for Updates…") { model.openReleases() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Preferences…") {
                model.showPreferences = true
                show("main")
            }
            .keyboardShortcut(",")
        }
        CommandGroup(after: .toolbar) {
            Button("Rescan") { Task { await model.rescan() } }
                .keyboardShortcut("r")
                .disabled(model.isScanning || model.phase != .idle)
        }
        // No help book (its default item only says "Help isn't available"): the website instead.
        CommandGroup(replacing: .help) {
            Button("Overstay Help") { model.openWebsite() }
            Button("What Overstay Reads") {
                model.showIntro = true
                show("main")
            }
            Divider()
            Button("Report a False Positive…") { model.openFalsePositiveIssue() }
            // For testers: counts and the processes that matched a signature, with no environment and no full home path.
            Button("Copy Diagnostics") { model.copyDiagnostics() }.disabled(model.scan == nil)
        }
    }

    private func show(_ id: String) {
        openWindow(id: id)
        activateApp()
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before SwiftUI creates the window; didFinish would be too late to drop the Tab menu items.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    /// The menu bar item keeps the app alive when the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
