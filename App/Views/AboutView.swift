import AppKit
import OverstayCore
import SwiftUI

/// The About window's content (a fixed 360pt column): icon, name, version, what it is, and the "not affiliated" line.
/// Needs `AppModel` in the environment. Links go through the model, the only place that opens URLs (BUILD_PLAN §3.1).
struct AboutView: View {
    @EnvironmentObject private var model: AppModel

    /// The tools Overstay detects, from the same list the UI prints (named descriptively, never as a credit).
    private static let detected = [AgentKind.claudeCode, .codex, .cursor, .zed, .windsurf, .vscode, .gemini]
        .map(\.displayName).joined(separator: ", ")

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "Version \(short)" : "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: Space.s) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(spacing: Space.xxs) {
                Text("Overstay").font(.system(size: 28, weight: .semibold)).tracking(-0.5)
                Text(Self.version).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Text("Finds the processes your AI coding agents left running, shows what they hold, and stops the ones you pick. Free and open source (MIT License). It makes no network connections and never reads the contents of your files.")
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.xs) {
                Button("Check for Updates") { model.openReleases() }
                Button("Report a False Positive") { model.openFalsePositiveIssue() }
            }
            .padding(.vertical, Space.xxs)
            VStack(spacing: Space.xs) {
                Text("It looks for leftovers from tools such as \(Self.detected). Their names belong to their owners. Overstay is not affiliated with or endorsed by any of the tools it detects.")
                    .fixedSize(horizontal: false, vertical: true)
                Text(ShareCardView.address).textSelection(.enabled)
                Text("© 2026 EverydayOpen")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(Space.xl)
        .frame(width: 360)
    }
}
