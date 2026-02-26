import GCalNotifierCore
import SwiftUI

/// Result returned from force sync operation.
struct ForceSyncResult: Sendable {
    let eventCount: Int
    let error: String?

    static func success(eventCount: Int) -> ForceSyncResult {
        ForceSyncResult(eventCount: eventCount, error: nil)
    }

    static func failure(_ error: String) -> ForceSyncResult {
        ForceSyncResult(eventCount: 0, error: error)
    }
}

/// Account settings combining OAuth setup and sync status in a single Form.
struct AccountTab: View {
    // OAuth state
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var authState: AuthState = .unconfigured
    @State private var isSigningIn = false
    @State private var oauthError: String?

    // Sync state
    @State private var lastSyncTime: Date?
    @State private var lastSyncError: String?
    @State private var isLoadingSync = false
    @State private var syncStatusMessage: String?

    private let oauthProvider: GoogleOAuthProvider
    private let onForceSync: (() async -> ForceSyncResult)?

    init(
        oauthProvider: GoogleOAuthProvider = GoogleOAuthProvider(),
        onForceSync: (() async -> ForceSyncResult)? = nil
    ) {
        self.oauthProvider = oauthProvider
        self.onForceSync = onForceSync
    }

    var body: some View {
        Form {
            Section("Google Calendar Setup") {
                self.setupInstructions
            }

            if !self.authState.canMakeApiCalls {
                Section("OAuth Credentials") {
                    self.credentialsForm
                }
            }

            Section("Connection Status") {
                self.connectionStatus
            }

            if let error = oauthError {
                Section {
                    self.oauthErrorView(error)
                }
            }

            Section("Sync Status") {
                self.syncStatusSection
            }
        }
        .formStyle(.grouped)
        .task { await self.loadInitialState() }
        .task { await self.pollAuthState() }
    }

    // MARK: - Setup Instructions

    private var setupInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("To connect your Google Calendar, you'll need to create OAuth credentials:")
                .foregroundStyle(.secondary)

            self.instructionStep(
                number: 1,
                text: "Go to Google Cloud Console",
                url: URL(string: "https://console.cloud.google.com/apis/credentials")
            )
            self.instructionStep(
                number: 2,
                text: "Create a new project (or select an existing one)"
            )
            self.instructionStep(
                number: 3,
                text: "Enable the Google Calendar API",
                url: URL(string: "https://console.cloud.google.com/apis/library/calendar-json.googleapis.com")
            )
            self.instructionStep(
                number: 4,
                text: "Create OAuth 2.0 Desktop credentials"
            )
            self.instructionStep(
                number: 5,
                text: "Copy the Client ID and Client Secret below"
            )
        }
        .padding(.vertical, 4)
    }

    private func instructionStep(number: Int, text: String, url: URL? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)

            if let url {
                Link(text, destination: url)
            } else {
                Text(text)
            }
        }
    }

    // MARK: - Credentials Form

    @ViewBuilder
    private var credentialsForm: some View {
        TextField("Client ID", text: self.$clientId)
            .textFieldStyle(.roundedBorder)
            .disabled(self.isSigningIn)
            .autocorrectionDisabled()

        SecureField("Client Secret", text: self.$clientSecret)
            .textFieldStyle(.roundedBorder)
            .disabled(self.isSigningIn)
    }

    // MARK: - Connection Status

    private var connectionStatus: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(self.statusColor)
                    .frame(width: 10, height: 10)
                Text(self.statusText)
                    .foregroundStyle(self.statusTextColor)
            }
            Spacer()
            self.actionButton
        }
    }

    private var statusColor: Color {
        switch self.authState {
        case .authenticated: .green
        case .authenticating: .orange
        case .expired: .yellow
        case .invalid: .red
        case .unconfigured, .configured: .gray
        }
    }

    private var statusText: String {
        switch self.authState {
        case .unconfigured: "Not configured"
        case .configured: "Ready to sign in"
        case .authenticating: "Signing in..."
        case .authenticated: "Connected"
        case .expired: "Session expired (will refresh)"
        case .invalid: "Re-authentication required"
        }
    }

    private var statusTextColor: Color {
        switch self.authState {
        case .authenticated: .primary
        case .invalid: .red
        default: .secondary
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if self.authState.canMakeApiCalls {
            Button("Sign Out", role: .destructive) {
                Task { await self.signOut() }
            }
            .disabled(self.isSigningIn)
            .pointerCursor()
        } else {
            Button(self.authState == .authenticating ? "Signing In..." : "Sign In") {
                Task { await self.signIn() }
            }
            .disabled(!self.canSignIn || self.isSigningIn)
            .buttonStyle(.borderedProminent)
            .pointerCursor()
        }
    }

    private var canSignIn: Bool {
        !self.clientId.isEmpty && !self.clientSecret.isEmpty
    }

    // MARK: - OAuth Error

    private func oauthErrorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.red)
            Spacer()
            Button("Dismiss") {
                self.oauthError = nil
            }
            .buttonStyle(.borderless)
            .pointerCursor()
        }
    }

    // MARK: - Sync Status

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

        if let message = syncStatusMessage {
            HStack {
                if self.isLoadingSync {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Text(message)
                    .foregroundColor(self.isLoadingSync ? .secondary : .green)
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
        .pointerCursor()
        .disabled(self.isLoadingSync || !self.authState.canMakeApiCalls)
        .help("Clears all sync tokens and performs a fresh calendar sync")
    }
}

// MARK: - AccountTab Actions

extension AccountTab {
    func loadInitialState() async {
        do {
            try await self.oauthProvider.loadStoredCredentials()
            self.authState = await self.oauthProvider.state
        } catch {
            self.oauthError = "Failed to load credentials: \(error.localizedDescription)"
        }

        do {
            let appState = try AppStateStore()
            self.lastSyncTime = try await appState.getLastFullSync()
        } catch {
            self.lastSyncError = "Failed to load sync status"
        }
    }

    func pollAuthState() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            self.authState = await self.oauthProvider.state
        }
    }

    func signIn() async {
        self.isSigningIn = true
        self.oauthError = nil

        do {
            if !self.authState.hasCredentials {
                try await self.oauthProvider.configure(
                    clientId: self.clientId,
                    clientSecret: self.clientSecret
                )
            }
            self.authState = await self.oauthProvider.state

            try await self.oauthProvider.authenticate()
            self.authState = await self.oauthProvider.state

            self.clientId = ""
            self.clientSecret = ""
        } catch let error as OAuthError {
            self.handleOAuthError(error)
        } catch {
            self.oauthError = error.localizedDescription
        }

        self.authState = await self.oauthProvider.state
        self.isSigningIn = false
    }

    func signOut() async {
        self.isSigningIn = true
        self.oauthError = nil

        do {
            try await self.oauthProvider.signOut()
            self.authState = await self.oauthProvider.state
        } catch {
            self.oauthError = "Sign out failed: \(error.localizedDescription)"
        }

        self.isSigningIn = false
    }

    func handleOAuthError(_ error: OAuthError) {
        switch error {
        case .userCancelled:
            self.oauthError = "Sign-in was cancelled."
        case .invalidCredentials:
            self.oauthError = "Invalid credentials. Please check your Client ID and Secret."
        case .notConfigured:
            self.oauthError = "Please enter your OAuth credentials first."
        case let .authenticationFailed(message):
            self.oauthError = "Authentication failed: \(message)"
        case let .tokenRefreshFailed(message):
            self.oauthError = "Token refresh failed: \(message)"
        case let .networkError(message):
            self.oauthError = "Network error: \(message)"
        case .notAuthenticated:
            self.oauthError = "Please sign in first."
        case let .keychainError(keychainError):
            self.oauthError = "Keychain error: \(keychainError)"
        case let .serverError(code, message):
            self.oauthError = "Server error (\(code)): \(message). Please try again."
        }
    }

    func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    func forceFullSync() async {
        guard let onForceSync else {
            self.lastSyncError = "Sync not available"
            return
        }

        self.isLoadingSync = true
        self.syncStatusMessage = "Syncing..."
        self.lastSyncError = nil
        defer { self.isLoadingSync = false }

        let result = await onForceSync()

        if let error = result.error {
            self.lastSyncError = error
            self.syncStatusMessage = nil
        } else {
            self.lastSyncTime = Date()
            self.syncStatusMessage = "Synced \(result.eventCount) events"
        }
    }
}
