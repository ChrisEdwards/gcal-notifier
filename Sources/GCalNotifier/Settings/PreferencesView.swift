import GCalNotifierCore
import SwiftUI

/// Main preferences window with tabbed interface for all application settings.
struct PreferencesView: View {
    @State private var settings: SettingsStore
    private let onForceSync: (() async -> ForceSyncResult)?

    init(settings: SettingsStore = SettingsStore(), onForceSync: (() async -> ForceSyncResult)? = nil) {
        self._settings = State(initialValue: settings)
        self.onForceSync = onForceSync
    }

    var body: some View {
        TabView {
            GeneralTab(settings: self.settings)
                .tabItem { Label("General", systemImage: "gear") }

            SoundsTab(settings: self.settings)
                .tabItem { Label("Sounds", systemImage: "speaker.wave.2") }

            CalendarsTab(settings: self.settings)
                .tabItem { Label("Calendars", systemImage: "calendar") }

            FilteringTab(settings: self.settings)
                .tabItem { Label("Filtering", systemImage: "line.3.horizontal.decrease.circle") }

            ShortcutsTab(settings: self.settings)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            AccountTab(onForceSync: self.onForceSync)
                .tabItem { Label("Account", systemImage: "person.circle") }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General Tab

/// General settings including alert timing and startup preferences.
struct GeneralTab: View {
    @Bindable var settings: SettingsStore
    @State private var launchAtLoginStatus: LaunchAtLoginStatus = .disabled

    var body: some View {
        Form {
            Section("Alert Timing") {
                self.alertTimingSection
            }

            Section("Startup") {
                self.launchAtLoginSection

                Toggle(
                    "Suppress alerts during screen sharing",
                    isOn: self.$settings.suppressDuringScreenShare
                )
            }
        }
        .formStyle(.grouped)
        .task {
            self.launchAtLoginStatus = LaunchAtLoginManager.shared.checkStatus()
        }
    }

    @ViewBuilder
    private var launchAtLoginSection: some View {
        let binding = Binding(get: { self.launchAtLoginStatus.isEnabled },
                              set: { self.launchAtLoginStatus = LaunchAtLoginManager.shared.setEnabled($0) })
        Toggle("Launch at login", isOn: binding)
        if case .requiresApproval = self.launchAtLoginStatus {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text("Approval required").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Open Settings") { LaunchAtLoginManager.shared.openLoginItemsSettings() }
                    .buttonStyle(.link).font(.caption).pointerCursor()
            }
        } else if case let .error(msg) = self.launchAtLoginStatus {
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).font(.caption)
        }
    }

    @ViewBuilder
    private var alertTimingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stage 1 Alert")
                Spacer()
                Text(self.formatMinutes(self.settings.alertStage1Minutes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(self.settings.alertStage1Minutes) },
                    set: { self.settings.alertStage1Minutes = Int($0) }
                ),
                in: 0 ... 30,
                step: 1
            )
            Text("First reminder before meeting starts (0 = disabled)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stage 2 Alert")
                Spacer()
                Text(self.formatMinutes(self.settings.alertStage2Minutes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(self.settings.alertStage2Minutes) },
                    set: { self.settings.alertStage2Minutes = Int($0) }
                ),
                in: 0 ... 15,
                step: 1
            )
            Text("Urgent reminder before meeting starts (0 = disabled)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes == 0 {
            "Disabled"
        } else if minutes == 1 {
            "1 minute"
        } else {
            "\(minutes) minutes"
        }
    }
}

// MARK: - Sounds Tab

/// Sound settings for alert stages.
struct SoundsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                SoundCard(
                    title: "Stage 1 Alert",
                    subtitle: "First reminder before meeting",
                    icon: "bell",
                    iconColor: .blue,
                    selection: self.$settings.stage1Sound,
                    customSoundPath: self.settings.customSoundPath
                )
            }

            Section {
                SoundCard(
                    title: "Stage 2 Alert",
                    subtitle: "Urgent reminder before meeting",
                    icon: "bell.badge.fill",
                    iconColor: .orange,
                    selection: self.$settings.stage2Sound,
                    customSoundPath: self.settings.customSoundPath
                )
            }

            Section("Custom Sound") {
                self.customSoundSection
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var customSoundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: self.settings.customSoundPath != nil ? "music.note" : "music.note.list")
                    .font(.title2)
                    .foregroundStyle(self.settings.customSoundPath != nil ? .green : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    if let path = settings.customSoundPath {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Custom sound loaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No custom sound")
                            .foregroundStyle(.secondary)
                        Text("Add your own audio file")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if self.settings.customSoundPath != nil {
                    Button {
                        self.settings.customSoundPath = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove custom sound")
                }

                Button("Choose...") {
                    self.selectCustomSound()
                }
                .controlSize(.small)
                .pointerCursor()
            }
        }
    }

    private func selectCustomSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            self.settings.customSoundPath = url.path
        }
    }
}

/// A styled card component for sound selection with preview capability.
private struct SoundCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    @Binding var selection: String
    let customSoundPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: self.icon)
                    .font(.title2)
                    .foregroundStyle(self.iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(self.title)
                        .fontWeight(.medium)
                    Text(self.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Picker("", selection: self.$selection) {
                    ForEach(BuiltInSound.allCases, id: \.rawValue) { sound in
                        Label(sound.displayName, systemImage: self.soundIcon(for: sound))
                            .tag(sound.rawValue)
                    }
                    if self.customSoundPath != nil {
                        Divider()
                        Label("Custom Sound", systemImage: "music.note")
                            .tag("custom")
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .frame(height: 28)

                Button {
                    SoundPlayer.shared.play(named: self.selection, customPath: self.customSoundPath)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(self.iconColor)
                }
                .buttonStyle(.borderless)
                .help("Preview sound")
            }
        }
        .padding(.vertical, 4)
    }

    private func soundIcon(for sound: BuiltInSound) -> String {
        switch sound {
        case .glass: "drop.fill"
        case .hero: "star.fill"
        case .ping: "bell.fill"
        case .pop: "bubble.fill"
        case .funk: "guitars.fill"
        case .blow: "wind"
        case .bottle: "waterbottle.fill"
        case .purr: "cat.fill"
        case .submarine: "water.waves"
        case .tink: "wand.and.stars"
        }
    }
}

// MARK: - Calendars Tab

/// Calendar selection for which calendars to monitor.
struct CalendarsTab: View {
    @Bindable var settings: SettingsStore
    @State private var newCalendarId = ""

    var body: some View {
        Form {
            Section {
                Text(
                    "Select which calendars should trigger meeting alerts. Leave empty to monitor all calendars."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section("Enabled Calendars") {
                if self.settings.enabledCalendars.isEmpty {
                    Text("All calendars enabled")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(self.settings.enabledCalendars, id: \.self) { calendarId in
                        HStack {
                            Text(calendarId)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                self.removeCalendar(calendarId)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section("Add Calendar") {
                HStack {
                    TextField("Calendar ID", text: self.$newCalendarId)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        self.addCalendar()
                    }
                    .disabled(self.newCalendarId.trimmingCharacters(in: .whitespaces).isEmpty)
                    .pointerCursor()
                }

                Text("Enter the calendar ID (email address) to monitor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func addCalendar() {
        let calendarId = self.newCalendarId.trimmingCharacters(in: .whitespaces)
        guard !calendarId.isEmpty, !self.settings.enabledCalendars.contains(calendarId) else {
            return
        }
        self.settings.enabledCalendars.append(calendarId)
        self.newCalendarId = ""
    }

    private func removeCalendar(_ calendarId: String) {
        self.settings.enabledCalendars.removeAll { $0 == calendarId }
    }
}

// MARK: - Filtering Tab

/// Keyword-based event filtering configuration.
struct FilteringTab: View {
    @Bindable var settings: SettingsStore
    @State private var newBlockedKeyword = ""
    @State private var newForceAlertKeyword = ""

    var body: some View {
        Form {
            Section("Blocked Keywords") {
                Text("Events containing these keywords will never trigger alerts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                self.keywordList(
                    keywords: self.$settings.blockedKeywords,
                    newKeyword: self.$newBlockedKeyword,
                    placeholder: "Add blocked keyword"
                )
            }

            Section("Force-Alert Keywords") {
                Text("Events with these keywords will alert even without a video link.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                self.keywordList(
                    keywords: self.$settings.forceAlertKeywords,
                    newKeyword: self.$newForceAlertKeyword,
                    placeholder: "Add force-alert keyword"
                )
            }

            Section {
                Text("Blocked keywords override force-alert keywords. Matching is case-insensitive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func keywordList(
        keywords: Binding<[String]>,
        newKeyword: Binding<String>,
        placeholder: String
    ) -> some View {
        if keywords.wrappedValue.isEmpty {
            Text("No keywords configured")
                .foregroundStyle(.secondary)
                .italic()
        } else {
            ForEach(keywords.wrappedValue, id: \.self) { keyword in
                HStack {
                    Text(keyword)
                    Spacer()
                    Button {
                        keywords.wrappedValue.removeAll { $0 == keyword }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }

        HStack {
            TextField(placeholder, text: newKeyword)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    self.addKeyword(to: keywords, from: newKeyword)
                }

            Button("Add") {
                self.addKeyword(to: keywords, from: newKeyword)
            }
            .disabled(newKeyword.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            .pointerCursor()
        }
    }

    private func addKeyword(to keywords: Binding<[String]>, from newKeyword: Binding<String>) {
        let keyword = newKeyword.wrappedValue.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty, !keywords.wrappedValue.contains(keyword) else {
            return
        }
        keywords.wrappedValue.append(keyword)
        newKeyword.wrappedValue = ""
    }
}
