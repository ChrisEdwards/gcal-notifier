import GCalNotifierCore
import SwiftUI

/// Main preferences window with tabbed interface for all application settings.
struct PreferencesView: View {
    @State private var settings: SettingsStore

    init(settings: SettingsStore = SettingsStore()) {
        self._settings = State(initialValue: settings)
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

            AccountTab()
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
                    .buttonStyle(.link).font(.caption)
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
    @State private var isPlayingStage1 = false
    @State private var isPlayingStage2 = false

    private let builtInSounds = [
        "gentle-chime": "Gentle Chime",
        "urgent-tone": "Urgent Tone",
        "soft-bell": "Soft Bell",
        "digital-alert": "Digital Alert",
        "system-default": "System Default",
    ]

    var body: some View {
        Form {
            Section("Stage 1 Sound") {
                self.soundPicker(
                    selection: self.$settings.stage1Sound,
                    isPlaying: self.$isPlayingStage1
                )
            }

            Section("Stage 2 Sound") {
                self.soundPicker(
                    selection: self.$settings.stage2Sound,
                    isPlaying: self.$isPlayingStage2
                )
            }

            Section("Custom Sound") {
                self.customSoundSection
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func soundPicker(selection: Binding<String>, isPlaying _: Binding<Bool>) -> some View {
        HStack {
            Picker("Sound", selection: selection) {
                ForEach(Array(self.builtInSounds.keys.sorted()), id: \.self) { key in
                    Text(self.builtInSounds[key] ?? key).tag(key)
                }
                if self.settings.customSoundPath != nil {
                    Text("Custom Sound").tag("custom")
                }
            }

            Button {
                self.playSound(selection.wrappedValue)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("Test sound")
        }
    }

    @ViewBuilder
    private var customSoundSection: some View {
        HStack {
            if let path = settings.customSoundPath {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No custom sound selected")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Choose...") {
                self.selectCustomSound()
            }

            if self.settings.customSoundPath != nil {
                Button("Clear") {
                    self.settings.customSoundPath = nil
                }
            }
        }
    }

    private func playSound(_: String) {
        // TODO: Implement sound playback via SoundPlayer
        NSSound.beep()
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

// MARK: - Account Tab

/// OAuth account management and sync status.
struct AccountTab: View {
    @State private var authState: AuthState = .unconfigured
    @State private var lastSyncTime: Date?
    @State private var lastSyncError: String?
    @State private var isLoadingSync = false

    private let oauthProvider: GoogleOAuthProvider

    init(oauthProvider: GoogleOAuthProvider = GoogleOAuthProvider()) {
        self.oauthProvider = oauthProvider
    }

    var body: some View {
        Form {
            Section("Google Account") {
                OAuthSetupView(oauthProvider: self.oauthProvider)
            }

            Section("Sync Status") {
                self.syncStatusSection
            }
        }
        .formStyle(.grouped)
        .task {
            await self.loadSyncStatus()
        }
    }

    @ViewBuilder
    private var syncStatusSection: some View {
        LabeledContent("Last sync") {
            if let lastSync = lastSyncTime {
                Text(self.formatDate(lastSync))
            } else {
                Text("Never")
                    .foregroundStyle(.secondary)
            }
        }

        if let error = lastSyncError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(error)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }

        Button("Force Full Sync") {
            Task { await self.forceFullSync() }
        }
        .disabled(self.isLoadingSync || !self.authState.canMakeApiCalls)
        .help("Clears all sync tokens and performs a fresh calendar sync")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadSyncStatus() async {
        self.authState = await self.oauthProvider.state

        do {
            let appState = try AppStateStore()
            self.lastSyncTime = try await appState.getLastFullSync()
        } catch {
            self.lastSyncError = "Failed to load sync status"
        }
    }

    private func forceFullSync() async {
        self.isLoadingSync = true
        defer { self.isLoadingSync = false }

        do {
            let appState = try AppStateStore()
            try await appState.clearAllSyncTokens()
            self.lastSyncError = nil
            // TODO: Trigger actual sync via SyncEngine when available
        } catch {
            self.lastSyncError = "Failed to clear sync tokens: \(error.localizedDescription)"
        }
    }
}
