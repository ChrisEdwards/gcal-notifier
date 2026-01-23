import Foundation
import Testing

@testable import GCalNotifierCore

// MARK: - Test Helpers

struct TestContext {
    let provider: GoogleOAuthProvider
    let keychainManager: KeychainManager
    let httpClient: MockHTTPClient
    let browserOpener: MockBrowserOpener
    let callbackServer: MockCallbackServer
}

private func makeTestContext() async -> TestContext {
    let testService = "com.gcal-notifier.auth.tests.\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString)"
    let keychainManager = KeychainManager(service: testService)
    let httpClient = MockHTTPClient()
    let browserOpener = MockBrowserOpener()
    let callbackServer = MockCallbackServer()
    let callbackServerFactory = MockCallbackServerFactory(mockServer: callbackServer)

    // Wire up browser opener to capture state and pass to callback server
    browserOpener.onOpen = { url in
        Task {
            await callbackServer.captureState(from: url)
        }
    }

    let provider = GoogleOAuthProvider(
        keychainManager: keychainManager,
        httpClient: httpClient,
        browserOpener: browserOpener,
        callbackServerFactory: callbackServerFactory
    )

    return TestContext(
        provider: provider,
        keychainManager: keychainManager,
        httpClient: httpClient,
        browserOpener: browserOpener,
        callbackServer: callbackServer
    )
}

private func cleanup(_ keychainManager: KeychainManager) async {
    try? await keychainManager.deleteAll()
}

private func makeTokenResponseJSON(
    accessToken: String = "test-access-token",
    refreshToken: String? = "test-refresh-token",
    expiresIn: Int = 3600
) -> Data {
    var json = """
    {
        "access_token": "\(accessToken)",
        "expires_in": \(expiresIn),
        "token_type": "Bearer"
    }
    """

    if let refreshToken {
        json = """
        {
            "access_token": "\(accessToken)",
            "refresh_token": "\(refreshToken)",
            "expires_in": \(expiresIn),
            "token_type": "Bearer"
        }
        """
    }

    return Data(json.utf8)
}

// MARK: - Tests

@Suite("GoogleOAuthProvider Tests", .serialized)
struct GoogleOAuthProviderTests {
    // MARK: - Initial State Tests

    @Test("Initial state is unconfigured")
    func initialStateIsUnconfigured() async {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        let state = await ctx.provider.state
        #expect(state == .unconfigured)
    }

    // MARK: - Configure Tests

    @Test("Configure transitions to configured state")
    func configureTransitionsToConfigured() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        try await ctx.provider.configure(clientId: "test-client-id", clientSecret: "test-secret")

        let state = await ctx.provider.state
        #expect(state == .configured)
    }

    @Test("Configure stores credentials in Keychain")
    func configureStoresCredentials() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        try await ctx.provider.configure(clientId: "test-client-id", clientSecret: "test-secret")

        let stored = try await ctx.keychainManager.loadClientCredentials()
        #expect(stored?.clientId == "test-client-id")
        #expect(stored?.clientSecret == "test-secret")
    }

    @Test("Configure with empty client ID throws invalidCredentials")
    func configureEmptyClientIdThrows() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        await #expect(throws: OAuthError.invalidCredentials) {
            try await ctx.provider.configure(clientId: "", clientSecret: "test-secret")
        }
    }

    @Test("Configure with empty client secret throws invalidCredentials")
    func configureEmptyClientSecretThrows() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        await #expect(throws: OAuthError.invalidCredentials) {
            try await ctx.provider.configure(clientId: "test-id", clientSecret: "")
        }
    }

    // MARK: - Load Stored Credentials Tests

    @Test("LoadStoredCredentials with tokens transitions to authenticated")
    func loadStoredCredentialsWithTokensTransitionsToAuthenticated() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        let credentials = OAuthClientCredentials(clientId: "test-id", clientSecret: "test-secret")
        try await ctx.keychainManager.saveClientCredentials(credentials)

        let tokens = OAuthTokens(
            accessToken: "test-access",
            refreshToken: "test-refresh",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try await ctx.keychainManager.saveTokens(tokens)

        try await ctx.provider.loadStoredCredentials()

        let state = await ctx.provider.state
        #expect(state == .authenticated)
    }

    @Test("LoadStoredCredentials with expired tokens transitions to expired")
    func loadStoredCredentialsWithExpiredTokensTransitionsToExpired() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        let credentials = OAuthClientCredentials(clientId: "test-id", clientSecret: "test-secret")
        try await ctx.keychainManager.saveClientCredentials(credentials)

        let tokens = OAuthTokens(
            accessToken: "test-access",
            refreshToken: "test-refresh",
            expiresAt: Date().addingTimeInterval(-60)
        )
        try await ctx.keychainManager.saveTokens(tokens)

        try await ctx.provider.loadStoredCredentials()

        let state = await ctx.provider.state
        #expect(state == .expired)
    }

    @Test("LoadStoredCredentials with no tokens transitions to configured")
    func loadStoredCredentialsWithNoTokensTransitionsToConfigured() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        let credentials = OAuthClientCredentials(clientId: "test-id", clientSecret: "test-secret")
        try await ctx.keychainManager.saveClientCredentials(credentials)

        try await ctx.provider.loadStoredCredentials()

        let state = await ctx.provider.state
        #expect(state == .configured)
    }

    @Test("LoadStoredCredentials with no credentials remains unconfigured")
    func loadStoredCredentialsWithNoCredentialsRemainsUnconfigured() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        try await ctx.provider.loadStoredCredentials()

        let state = await ctx.provider.state
        #expect(state == .unconfigured)
    }

    // MARK: - Authenticate Tests

    @Test("Authenticate when unconfigured throws notConfigured")
    func authenticateWhenUnconfiguredThrows() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        await #expect(throws: OAuthError.notConfigured) {
            try await ctx.provider.authenticate()
        }
    }

    @Test("Authenticate with user cancellation throws userCancelled")
    func authenticateUserCancelled() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        try await ctx.provider.configure(clientId: "test-client-id", clientSecret: "test-secret")

        // Configure callback server to return access_denied error
        await ctx.callbackServer.configureForError("access_denied")

        await #expect(throws: OAuthError.userCancelled) {
            try await ctx.provider.authenticate()
        }

        let state = await ctx.provider.state
        #expect(state == .configured)
    }

    // MARK: - Get Access Token Tests

    @Test("GetAccessToken when authenticated returns token")
    func getAccessTokenWhenAuthenticatedReturnsToken() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        let credentials = OAuthClientCredentials(clientId: "test-id", clientSecret: "test-secret")
        try await ctx.keychainManager.saveClientCredentials(credentials)

        let tokens = OAuthTokens(
            accessToken: "my-access-token",
            refreshToken: "my-refresh-token",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try await ctx.keychainManager.saveTokens(tokens)

        try await ctx.provider.loadStoredCredentials()

        let token = try await ctx.provider.getAccessToken()
        #expect(token == "my-access-token")
    }

    @Test("GetAccessToken when not authenticated throws notAuthenticated")
    func getAccessTokenWhenNotAuthenticatedThrows() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        await #expect(throws: OAuthError.notAuthenticated) {
            try await ctx.provider.getAccessToken()
        }
    }

    @Test("GetAccessToken when expiring soon refreshes proactively")
    func getAccessTokenExpiringRefreshesProactively() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        let credentials = OAuthClientCredentials(clientId: "test-id", clientSecret: "test-secret")
        try await ctx.keychainManager.saveClientCredentials(credentials)

        let tokens = OAuthTokens(
            accessToken: "old-access-token",
            refreshToken: "my-refresh-token",
            expiresAt: Date().addingTimeInterval(120) // 2 minutes - within 5 min threshold
        )
        try await ctx.keychainManager.saveTokens(tokens)

        try await ctx.provider.loadStoredCredentials()

        await ctx.httpClient.queueResponse(
            data: makeTokenResponseJSON(accessToken: "new-access-token"),
            statusCode: 200
        )

        let token = try await ctx.provider.getAccessToken()
        #expect(token == "new-access-token")

        let requests = await ctx.httpClient.requestsReceived
        #expect(requests.count == 1)
    }

    @Test("GetAccessToken refresh fails transitions to invalid")
    func getAccessTokenRefreshFailsTransitionsToInvalid() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        let credentials = OAuthClientCredentials(clientId: "test-id", clientSecret: "test-secret")
        try await ctx.keychainManager.saveClientCredentials(credentials)

        let tokens = OAuthTokens(
            accessToken: "old-access-token",
            refreshToken: "my-refresh-token",
            expiresAt: Date().addingTimeInterval(60) // 1 minute - will trigger refresh
        )
        try await ctx.keychainManager.saveTokens(tokens)

        try await ctx.provider.loadStoredCredentials()

        await ctx.httpClient.queueResponse(data: Data("Error".utf8), statusCode: 401)

        do {
            _ = try await ctx.provider.getAccessToken()
            Issue.record("Expected tokenRefreshFailed error")
        } catch {
            // Expected
        }

        let state = await ctx.provider.state
        #expect(state == .invalid)
    }

    // MARK: - Sign Out Tests

    @Test("SignOut clears tokens and transitions to unconfigured")
    func signOutClearsTokens() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        let credentials = OAuthClientCredentials(clientId: "test-id", clientSecret: "test-secret")
        try await ctx.keychainManager.saveClientCredentials(credentials)

        let tokens = OAuthTokens(
            accessToken: "test-access",
            refreshToken: "test-refresh",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try await ctx.keychainManager.saveTokens(tokens)

        try await ctx.provider.loadStoredCredentials()

        try await ctx.provider.signOut()

        let state = await ctx.provider.state
        #expect(state == .unconfigured)

        let storedCreds = try await ctx.keychainManager.loadClientCredentials()
        let storedTokens = try await ctx.keychainManager.loadTokens()
        #expect(storedCreds == nil)
        #expect(storedTokens == nil)
    }

    @Test("SignOut when already signed out succeeds")
    func signOutWhenAlreadySignedOutSucceeds() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        try await ctx.provider.signOut()

        let state = await ctx.provider.state
        #expect(state == .unconfigured)
    }

    // MARK: - isAuthenticated Tests

    @Test("isAuthenticated returns true when authenticated")
    func isAuthenticatedReturnsTrueWhenAuthenticated() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        let credentials = OAuthClientCredentials(clientId: "test-id", clientSecret: "test-secret")
        try await ctx.keychainManager.saveClientCredentials(credentials)

        let tokens = OAuthTokens(
            accessToken: "test-access",
            refreshToken: "test-refresh",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try await ctx.keychainManager.saveTokens(tokens)

        try await ctx.provider.loadStoredCredentials()

        let isAuthenticated = await ctx.provider.isAuthenticated
        #expect(isAuthenticated == true)
    }

    @Test("isAuthenticated returns false when unconfigured")
    func isAuthenticatedReturnsFalseWhenUnconfigured() async {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        let isAuthenticated = await ctx.provider.isAuthenticated
        #expect(isAuthenticated == false)
    }

    @Test("isAuthenticated returns true when expired (can still make calls)")
    func isAuthenticatedReturnsTrueWhenExpired() async throws {
        let ctx = await makeTestContext()
        defer { Task { await cleanup(ctx.keychainManager) } }

        let credentials = OAuthClientCredentials(clientId: "test-id", clientSecret: "test-secret")
        try await ctx.keychainManager.saveClientCredentials(credentials)

        let tokens = OAuthTokens(
            accessToken: "test-access",
            refreshToken: "test-refresh",
            expiresAt: Date().addingTimeInterval(-60)
        )
        try await ctx.keychainManager.saveTokens(tokens)

        try await ctx.provider.loadStoredCredentials()

        let isAuthenticated = await ctx.provider.isAuthenticated
        #expect(isAuthenticated == true)
    }
}
