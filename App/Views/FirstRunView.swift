import AppKit
import OverstayCore
import SwiftUI

/// What Overstay reads and what it never does, before it reads anything (BUILD_PLAN §7.2: nothing is scanned until
/// "Continue"). A 480pt column over the room wash (docs/DESIGN.md §6.5). Also reachable from Help: pass `isSheet`.
struct FirstRunView: View {
    @EnvironmentObject private var model: AppModel
    /// True when shown from Help in a sheet: Continue then just dismisses it.
    var isSheet = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    private static let reads: [(symbol: String, text: String)] = [
        ("list.bullet.rectangle", "The list of running processes"),
        ("memorychip", "How much memory each one holds"),
        ("text.alignleft", "The arguments of your own processes, read in memory to spot agent tools"),
        ("folder", "Their working folders, to name the project (secret-looking values are hidden, nothing is saved)"),
    ]
    private static let never: [(symbol: String, text: String)] = [
        ("lock.open", "Asks for a permission"),
        ("wifi.slash", "Uses the network"),
        ("doc", "Touches your files"),
        ("power", "Installs a login item"),
        ("arrow.uturn.backward", "Brings a stopped process back"),
    ]

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.l)
                .frame(width: 480 + Space.xl * 2)
                .frame(maxWidth: .infinity)
        }
        // Continue stays in view however short the window is; the text above scrolls. Ideal height is for the Help sheet.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Space.xs) {
                Button("Continue") {
                    model.prefs.hasSeenFirstRun = true
                    if isSheet {
                        dismiss()
                    } else {
                        Task { if !model.isScanning { await model.rescan() } }
                    }
                }
                .buttonStyle(AmberButtonStyle())
                .keyboardShortcut(.defaultAction)

                Text("Overstay is not affiliated with or endorsed by any of the tools it detects.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.vertical, Space.s)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .frame(maxWidth: .infinity, minHeight: 320, idealHeight: 620, maxHeight: .infinity)
        .background(Room())
        .onAppear { withAnimation(reduceMotion ? Motion.standard(true) : Motion.hero.delay(0.1)) { arrived = true } }
    }

    private var content: some View {
        VStack(spacing: Space.m) {
            OnFloor(height: 96) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            }
            .modifier(HoverTilt(max: 8, glare: true))
            .offset(y: arrived || reduceMotion ? 0 : 24)
            .opacity(arrived ? 1 : 0)
            .accessibilityHidden(true)

            VStack(spacing: Space.xxs) {
                Text("What Overstay reads").font(.system(size: 28, weight: .semibold)).tracking(-0.5)
                Text("It finds the processes your AI coding agents left running and stops them when you say so.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            HStack(alignment: .top, spacing: Space.l) {
                column("Reads", Self.reads)
                Divider()
                column("Never", Self.never)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(Space.m)
            .surface(16)

            Text("Arguments are read in memory with secret-looking values hidden, and are never saved. Stopping a process cannot be undone: anything unsaved inside it is lost.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func column(_ title: String, _ items: [(symbol: String, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(.caption.weight(.semibold).smallCaps()).foregroundStyle(.secondary)   // VERIFY small caps with SF
                .accessibilityAddTraits(.isHeader)
            ForEach(items, id: \.text) { item in
                Label {
                    Text(item.text).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: item.symbol).foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
