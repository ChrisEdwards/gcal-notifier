import GCalNotifierCore
import KeyboardShortcuts
import SwiftUI

/// Global keyboard shortcuts configuration.
struct ShortcutsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Text("Configure global keyboard shortcuts for quick meeting actions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                Toggle("Enable keyboard shortcuts", isOn: self.$settings.shortcutsEnabled)

                KeyboardShortcuts.Recorder("Join next meeting:", name: .joinNextMeeting)
                    .disabled(!self.settings.shortcutsEnabled)

                KeyboardShortcuts.Recorder("Dismiss alert:", name: .dismissAlert)
                    .disabled(!self.settings.shortcutsEnabled)
            }

            Section("Defaults") {
                HStack {
                    Text("Default shortcuts:")
                    Spacer()
                    Text("Join: Cmd+Shift+J, Dismiss: Cmd+Shift+D")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Reset to Defaults") {
                    KeyboardShortcuts.reset(.joinNextMeeting, .dismissAlert)
                }
                .disabled(!self.settings.shortcutsEnabled)
                .pointerCursor()
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Join shortcut joins the next meeting with a video link.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Dismiss shortcut closes the current alert window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
