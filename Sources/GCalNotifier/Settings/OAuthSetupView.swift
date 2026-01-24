import GCalNotifierCore
import SwiftUI

/// Settings view for configuring OAuth credentials and managing sign-in.
///
/// This view provides:
/// - Step-by-step setup instructions with links
/// - Client ID/Secret input fields
/// - Sign-in button and status display
/// - Sign-out functionality
/// - Error display
struct OAuthSetupView: View {
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var authState: AuthState = .unconfigured
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    private let oauthProvider: GoogleOAuthProvider

    init(oauthProvider: GoogleOAuthProvider = GoogleOAuthProvider()) {
        self.oauthProvider = oauthProvider
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
                self.signInStatus
            }

            if let error = errorMessage {
                Section {
                    self.errorView(error)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500)
        .task {
            await self.loadInitialState()
        }
    }

    // MARK: - Setup Instructions

    @ViewBuilder
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

    @ViewBuilder
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

    // MARK: - Sign In Status

    @ViewBuilder
    private var signInStatus: some View {
        HStack {
            self.statusIndicator
            Spacer()
            self.actionButton
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(self.statusColor)
                .frame(width: 10, height: 10)

            Text(self.statusText)
                .foregroundStyle(self.statusTextColor)
        }
    }

    private var statusColor: Color {
        switch self.authState {
        case .authenticated:
            .green
        case .authenticating:
            .orange
        case .expired:
            .yellow
        case .invalid:
            .red
        case .unconfigured, .configured:
            .gray
        }
    }

    private var statusText: String {
        switch self.authState {
        case .unconfigured:
            "Not configured"
        case .configured:
            "Ready to sign in"
        case .authenticating:
            "Signing in..."
        case .authenticated:
            "Connected"
        case .expired:
            "Session expired (will refresh)"
        case .invalid:
            "Re-authentication required"
        }
    }

    private var statusTextColor: Color {
        switch self.authState {
        case .authenticated:
            .primary
        case .invalid:
            .red
        default:
            .secondary
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if self.authState.canMakeApiCalls {
            Button("Sign Out", role: .destructive) {
                Task { await self.signOut() }
            }
            .disabled(self.isSigningIn)
        } else {
            Button(self.authState == .authenticating ? "Signing In..." : "Sign In") {
                Task { await self.signIn() }
            }
            .disabled(!self.canSignIn || self.isSigningIn)
            .buttonStyle(.borderedProminent)
        }
    }

    private var canSignIn: Bool {
        !self.clientId.isEmpty && !self.clientSecret.isEmpty
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .foregroundStyle(.red)

            Spacer()

            Button("Dismiss") {
                self.errorMessage = nil
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Actions

    private func loadInitialState() async {
        do {
            try await self.oauthProvider.loadStoredCredentials()
            self.authState = await self.oauthProvider.state
        } catch {
            self.errorMessage = "Failed to load credentials: \(error.localizedDescription)"
        }
    }

    private func signIn() async {
        self.isSigningIn = true
        self.errorMessage = nil

        do {
            if !self.authState.hasCredentials {
                try await self.oauthProvider.configure(clientId: self.clientId, clientSecret: self.clientSecret)
            }
            self.authState = await self.oauthProvider.state

            try await self.oauthProvider.authenticate()
            self.authState = await self.oauthProvider.state

            self.clientId = ""
            self.clientSecret = ""
        } catch let error as OAuthError {
            handleOAuthError(error)
        } catch {
            self.errorMessage = error.localizedDescription
        }

        self.authState = await self.oauthProvider.state
        self.isSigningIn = false
    }

    private func signOut() async {
        self.isSigningIn = true
        self.errorMessage = nil

        do {
            try await self.oauthProvider.signOut()
            self.authState = await self.oauthProvider.state
        } catch {
            self.errorMessage = "Sign out failed: \(error.localizedDescription)"
        }

        self.isSigningIn = false
    }

    private func handleOAuthError(_ error: OAuthError) {
        switch error {
        case .userCancelled:
            self.errorMessage = "Sign-in was cancelled."
        case .invalidCredentials:
            self.errorMessage = "Invalid credentials. Please check your Client ID and Secret."
        case .notConfigured:
            self.errorMessage = "Please enter your OAuth credentials first."
        case let .authenticationFailed(message):
            self.errorMessage = "Authentication failed: \(message)"
        case let .tokenRefreshFailed(message):
            self.errorMessage = "Token refresh failed: \(message)"
        case let .networkError(message):
            self.errorMessage = "Network error: \(message)"
        case .notAuthenticated:
            self.errorMessage = "Please sign in first."
        case let .keychainError(keychainError):
            self.errorMessage = "Keychain error: \(keychainError)"
        case let .serverError(code, message):
            self.errorMessage = "Server error (\(code)): \(message). Please try again."
        }
    }
}
