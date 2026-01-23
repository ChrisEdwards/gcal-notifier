/// A protocol defining OAuth authentication provider capabilities.
///
/// `OAuthProvider` abstracts the authentication lifecycle for OAuth 2.0 providers,
/// enabling dependency injection and mocking for tests. Implementers must be actors
/// to ensure thread-safe state management.
///
/// ## Conformance
/// Types conforming to `OAuthProvider` must:
/// - Be actors (thread-safe by design)
/// - Be `Sendable` for safe passage across concurrency domains
/// - Manage an `AuthState` that reflects the current authentication status
///
/// ## Example Implementation
/// ```swift
/// public actor GoogleOAuthProvider: OAuthProvider {
///     public private(set) var state: AuthState = .unconfigured
///
///     public func configure(clientId: String, clientSecret: String) async throws {
///         // Store credentials and update state
///     }
///     // ... other methods
/// }
/// ```
///
/// ## Example Usage
/// ```swift
/// let provider: any OAuthProvider = GoogleOAuthProvider()
/// try await provider.configure(clientId: "...", clientSecret: "...")
/// try await provider.authenticate()
/// let token = try await provider.getAccessToken()
/// ```
public protocol OAuthProvider: Actor, Sendable {
    /// The current authentication state.
    ///
    /// This property reflects the OAuth lifecycle state and should be used
    /// to determine what UI to show and what actions are available.
    var state: AuthState { get async }

    /// Whether the provider is currently authenticated.
    ///
    /// Returns `true` when `state` is `.authenticated` or `.expired`.
    /// In the expired state, tokens can be refreshed automatically.
    var isAuthenticated: Bool { get async }

    /// Configures the provider with OAuth client credentials.
    ///
    /// This method stores the client credentials and transitions the state
    /// from `.unconfigured` to `.configured`. Credentials are stored securely
    /// in the Keychain.
    ///
    /// - Parameters:
    ///   - clientId: The OAuth client ID from Google Cloud Console.
    ///   - clientSecret: The OAuth client secret from Google Cloud Console.
    /// - Throws: `OAuthError.invalidCredentials` if credentials are empty.
    func configure(clientId: String, clientSecret: String) async throws

    /// Starts the OAuth authentication flow.
    ///
    /// This method opens the browser for user authorization and handles the
    /// callback. On success, the state transitions to `.authenticated`.
    ///
    /// - Throws: `OAuthError.authenticationFailed` if the flow fails.
    /// - Throws: `OAuthError.notConfigured` if credentials haven't been set.
    func authenticate() async throws

    /// Returns a valid access token, refreshing if necessary.
    ///
    /// If the current access token is expired or about to expire, this method
    /// proactively refreshes it before returning. This prevents 401 errors
    /// from disrupting the user experience.
    ///
    /// - Returns: A valid access token for API calls.
    /// - Throws: `OAuthError.notAuthenticated` if not authenticated.
    /// - Throws: `OAuthError.tokenRefreshFailed` if refresh fails.
    func getAccessToken() async throws -> String

    /// Signs out the user and clears all authentication data.
    ///
    /// This method removes all tokens and credentials from the Keychain
    /// and transitions the state to `.unconfigured`.
    func signOut() async throws
}

// MARK: - Default Implementations

public extension OAuthProvider {
    /// Default implementation checking if state allows API calls.
    var isAuthenticated: Bool {
        get async {
            await self.state.canMakeApiCalls
        }
    }
}

// MARK: - OAuthError

/// Errors that can occur during OAuth operations.
public enum OAuthError: Error, Equatable, Sendable {
    /// OAuth credentials have not been configured.
    case notConfigured
    /// The provided credentials are invalid (empty or malformed).
    case invalidCredentials
    /// User is not authenticated.
    case notAuthenticated
    /// The OAuth authentication flow failed.
    case authenticationFailed(String)
    /// Token refresh failed.
    case tokenRefreshFailed(String)
    /// User cancelled the authentication flow.
    case userCancelled
    /// Network error during OAuth operations.
    case networkError(String)
    /// Keychain operation failed.
    case keychainError(KeychainError)
}
