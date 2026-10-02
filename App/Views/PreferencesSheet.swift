import OverstayCore
import SwiftUI

/// Preferences (docs/DESIGN.md §6.5): a stock grouped `Form`, no custom surfaces. Nothing here can make Overstay touch
/// more than its rules allow: the never-touch list only adds protection, and the age gate only decides what counts as a
/// leftover. Changes are saved by `AppModel` as they are made. Notifications are not offered: nothing sends them yet.
struct PreferencesSheet: View {
    @EnvironmentObject private var model: AppModel
    @State private var entry = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("A leftover must be at least", selection: $model.prefs.ageGateMinutes) {
                        Text("10 minutes old").tag(10)
                        Text("30 minutes old").tag(30)
                        Text("1 hour old").tag(60)
                    }
                } header: {
                    Text("Leftovers")
                } footer: {
                    Text("A process that started more recently is shown as a Maybe, never as a leftover.")
                }

                Section {
                    ForEach(model.prefs.neverTouch, id: \.self) { item in
                        HStack {
                            Text(Scrub.tilde(item, home: NSHomeDirectory())).font(.system(.body, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: Space.xs)
                            Button { model.prefs.neverTouch.removeAll { $0 == item } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .help("Remove from the list")
                                .accessibilityLabel("Remove \(item)")
                        }
                    }
                    HStack {
                        TextField("Program name or folder", text: $entry).onSubmit(add)
                        Button("Add", action: add).disabled(!canAdd)
                    }
                } header: {
                    Text("Never touch")
                } footer: {
                    Text(invalid ? "Use a program name such as postgres, or a folder path starting with / or ~/."
                                 : "Overstay will never list or stop a program with one of these names, or anything running in one of these folders. This only adds to the protections built in.")
                }

                Section {
                    Toggle("Include project folder names on the share card", isOn: $model.prefs.shareIncludesProjectNames)
                } header: {
                    Text("Sharing")
                } footer: {
                    Text("Off by default: the card shows the number and the tools. A folder name can give away a client or a product.")
                }

                Section {
                    Picker("Rescan automatically", selection: $model.prefs.autoScanSeconds) {
                        Text("Every minute").tag(60)
                        Text("Every 5 minutes").tag(300)
                        Text("Only when I ask").tag(0)
                    }
                } header: {
                    Text("Scanning")
                } footer: {
                    Text("Only while Overstay's window or menu bar popover is open. There is no background helper.")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") { model.showPreferences = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Space.m)
        }
        .frame(width: 480, height: 540)
    }

    /// `~/dev/foo` becomes an absolute path, which is what the protected list compares against.
    private var normalized: String {
        let e = entry.trimmingCharacters(in: .whitespaces)
        return e.hasPrefix("~/") ? NSHomeDirectory() + e.dropFirst() : e
    }

    /// A name with a slash in it that is not a full path would never match anything.
    private var invalid: Bool { normalized.contains("/") && !normalized.hasPrefix("/") }

    private var canAdd: Bool { !normalized.isEmpty && !invalid && !model.prefs.neverTouch.contains(normalized) }

    private func add() {
        guard canAdd else { return }
        model.prefs.neverTouch.append(normalized)
        entry = ""
    }
}
