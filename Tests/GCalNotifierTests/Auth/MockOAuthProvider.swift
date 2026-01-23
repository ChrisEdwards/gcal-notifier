@testable import GCalNotifierCore

/// A mock OAuth provider for testing authentication flows.
///
/// `MockOAuthProvider` allows tests to simulate various authentication
/// scenarios without actual OAuth flows or Keychain access.
///
/// ## Usage
/// ```swift
/// let mock = MockOAuthProvider()
///
/// // Simulate successful authentication
/// try await mock.configure(clientId: "test", clientSecret: "test")
/// try await mock.authenticate()
///
/// // Verify state
/// let state = await mock.state
/// XCTAssertEqual(state, .authenticated)
/// ```
///
/// ## Simulating Errors
/// ```swift
/// let mock = MockOAuthProvider()
/// mock.authenticateError = .authenticationFailed("Simulated failure")
/// ```
public actor MockOAuthProvider: OAuthProvider {
    // MARK: - State

    public private(set) var state: AuthState = .unconfigured

    // MARK: - Recorded Calls

    /// Number of times `configure` was called.
    public private(set) var configureCallCount = 0

    /// Number of times `authenticate` was called.
    public private(set) var authenticateCallCount = 0

    /// Number of times `getAccessToken` was called.
    public private(set) var getAccessTokenCallCount = 0

    /// Number of times `signOut` was called.
    public private(set) var signOutCallCount = 0

    /// The last client ID passed to `configure`.
    public private(set) var lastConfiguredClientId: String?

    /// The last client secret passed to `configure`.
    public private(set) var lastConfiguredClientSecret: String?

    // MARK: - Stubbed Responses

    /// Error to throw from `configure`. If nil, configure succeeds.
    public var configureError: OAuthError?

    /// Error to throw from `authenticate`. If nil, authenticate succeeds.
    public var authenticateError: OAuthError?

    /// Error to throw from `getAccessToken`. If nil, returns `stubbedAccessToken`.
    public var getAccessTokenError: OAuthError?

    /// The access token to return from `getAccessToken`.
    public var stubbedAccessToken = "mock-access-token"

    /// Error to throw from `signOut`. If nil, signOut succeeds.
    public var signOutError: OAuthError?

    // MARK: - Initialization

    public init(initialState: AuthState = .unconfigured) {
        self.state = initialState
    }

    // MARK: - OAuthProvider

    public func configure(clientId: String, clientSecret: String) async throws {
        self.configureCallCount += 1
        self.lastConfiguredClientId = clientId
        self.lastConfiguredClientSecret = clientSecret

        if let error = configureError {
            throw error
        }

        guard !clientId.isEmpty, !clientSecret.isEmpty else {
            throw OAuthError.invalidCredentials
        }

        self.state = .configured
    }

    public func authenticate() async throws {
        self.authenticateCallCount += 1

        if let error = authenticateError {
            throw error
        }

        guard self.state != .unconfigured else {
            throw OAuthError.notConfigured
        }

        self.state = .authenticating
        // Simulate successful authentication
        self.state = .authenticated
    }

    public func getAccessToken() async throws -> String {
        self.getAccessTokenCallCount += 1

        if let error = getAccessTokenError {
            throw error
        }

        guard self.state.canMakeApiCalls else {
            throw OAuthError.notAuthenticated
        }

        return self.stubbedAccessToken
    }

    public func signOut() async throws {
        self.signOutCallCount += 1

        if let error = signOutError {
            throw error
        }

        self.state = .unconfigured
    }

    // MARK: - Test Helpers

    /// Directly sets the state for testing scenarios.
    public func setState(_ newState: AuthState) {
        self.state = newState
    }

    /// Resets all call counts and recorded values.
    public func reset() {
        self.configureCallCount = 0
        self.authenticateCallCount = 0
        self.getAccessTokenCallCount = 0
        self.signOutCallCount = 0
        self.lastConfiguredClientId = nil
        self.lastConfiguredClientSecret = nil
        self.configureError = nil
        self.authenticateError = nil
        self.getAccessTokenError = nil
        self.signOutError = nil
        self.stubbedAccessToken = "mock-access-token"
        self.state = .unconfigured
    }
}
