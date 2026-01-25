import Foundation
import OSLog

/// Full OAuth 2.0 implementation for Google Calendar API.
///
/// `GoogleOAuthProvider` handles the complete OAuth lifecycle:
/// - Storing client credentials in Keychain
/// - Opening browser for Google sign-in
/// - Receiving authorization code via localhost redirect
/// - Exchanging code for tokens
/// - Proactive token refresh (before expiry, not after 401)
public actor GoogleOAuthProvider: OAuthProvider {
    // MARK: - Constants

    private static let callbackPort: UInt16 = 8089
    private static let callbackPath = "/oauth/callback"
    private static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")
    private static let scope = "https://www.googleapis.com/auth/calendar.readonly"

    /// Refresh tokens proactively if they expire within this many seconds.
    private static let refreshThresholdSeconds: TimeInterval = 300

    // MARK: - State

    public private(set) var state: AuthState = .unconfigured

    // MARK: - Dependencies

    private let keychainManager: KeychainManager
    private let httpClient: HTTPClient
    private let browserOpener: BrowserOpener
    private let callbackServerFactory: CallbackServerFactory

    // MARK: - Internal State

    private var clientCredentials: OAuthClientCredentials?
    private var tokens: OAuthTokens?

    // MARK: - Initialization

    /// Creates a new GoogleOAuthProvider with default dependencies.
    public init() {
        self.keychainManager = KeychainManager.shared
        self.httpClient = URLSessionHTTPClient()
        self.browserOpener = SystemBrowserOpener()
        self.callbackServerFactory = LocalhostCallbackServerFactory(port: Self.callbackPort)
    }

    /// Creates a new GoogleOAuthProvider with injected dependencies (for testing).
    public init(
        keychainManager: KeychainManager,
        httpClient: HTTPClient,
        browserOpener: BrowserOpener,
        callbackServerFactory: CallbackServerFactory
    ) {
        self.keychainManager = keychainManager
        self.httpClient = httpClient
        self.browserOpener = browserOpener
        self.callbackServerFactory = callbackServerFactory
    }

    // MARK: - OAuthProvider

    public func configure(clientId: String, clientSecret: String) async throws {
        guard !clientId.isEmpty, !clientSecret.isEmpty else { throw OAuthError.invalidCredentials }

        let credentials = OAuthClientCredentials(clientId: clientId, clientSecret: clientSecret)
        do {
            try await self.keychainManager.saveOAuthData(OAuthData(credentials: credentials, tokens: nil))
        } catch let error as KeychainError {
            throw OAuthError.keychainError(error)
        }
        self.clientCredentials = credentials
        self.state = .configured
    }

    public func authenticate() async throws {
        guard self.state != .unconfigured, let credentials = clientCredentials else {
            throw OAuthError.notConfigured
        }
        self.state = .authenticating

        do {
            let newTokens = try await self.performAuthenticationFlow(credentials: credentials)
            try await self.keychainManager.saveOAuthData(OAuthData(credentials: credentials, tokens: newTokens))
            self.tokens = newTokens
            self.state = .authenticated
        } catch let error as OAuthError {
            self.state = .configured
            throw error
        } catch {
            self.state = .configured
            throw OAuthError.authenticationFailed(error.localizedDescription)
        }
    }

    public func getAccessToken() async throws -> String {
        guard self.state.canMakeApiCalls else { throw OAuthError.notAuthenticated }
        if self.tokens == nil { self.tokens = try await self.keychainManager.loadTokens() }

        guard var currentTokens = tokens else {
            self.state = .invalid
            throw OAuthError.notAuthenticated
        }
        if currentTokens.expiresIn < Self.refreshThresholdSeconds {
            Logger.auth.debug("Token expires in \(Int(currentTokens.expiresIn))s, refreshing proactively")
            do {
                currentTokens = try await self.refreshTokens(currentTokens)
                self.tokens = currentTokens
                self.state = .authenticated
            } catch {
                let oauthError = Self.classifyRefreshError(error)
                Logger.auth.error("Token refresh failed: \(oauthError.localizedDescription)")
                self.state = oauthError.isTransient ? .expired : .invalid
                throw oauthError
            }
        }

        return currentTokens.accessToken
    }

    public func signOut() async throws {
        do {
            try await self.keychainManager.deleteAll()
        } catch let error as KeychainError {
            if error != .itemNotFound {
                throw OAuthError.keychainError(error)
            }
        }

        self.clientCredentials = nil
        self.tokens = nil
        self.state = .unconfigured
        Logger.auth.info("Signed out and cleared credentials")
    }

    // MARK: - Credential Loading

    /// Loads stored credentials and tokens from Keychain, updating state accordingly.
    /// Uses combined storage to minimize password prompts (single Keychain access).
    public func loadStoredCredentials() async throws {
        if self.clientCredentials != nil { return } // Already loaded

        guard let data = try await keychainManager.loadOAuthData() else {
            self.state = .unconfigured
            return
        }
        self.clientCredentials = data.credentials

        guard let storedTokens = data.tokens else {
            self.state = .configured
            return
        }
        self.tokens = storedTokens
        self.state = storedTokens.isExpired ? .expired : .authenticated
    }

    // MARK: - Private Methods

    private func performAuthenticationFlow(credentials: OAuthClientCredentials) async throws -> OAuthTokens {
        let callbackServer = self.callbackServerFactory.createServer()
        try await callbackServer.start()
        defer { Task { await callbackServer.stop() } }

        let stateParam = UUID().uuidString
        let redirectURI = "http://localhost:\(Self.callbackPort)\(Self.callbackPath)"

        guard let authURL = self.buildAuthorizationURL(
            credentials: credentials,
            redirectURI: redirectURI,
            state: stateParam
        ) else {
            throw OAuthError.authenticationFailed("Failed to build authorization URL")
        }

        self.browserOpener.open(authURL)
        Logger.auth.debug("Opened browser for authorization")

        let callbackResult = try await callbackServer.waitForCallback(timeout: 300)

        guard callbackResult.state == stateParam else {
            throw OAuthError.authenticationFailed("State parameter mismatch")
        }

        if let error = callbackResult.error {
            if error == "access_denied" { throw OAuthError.userCancelled }
            throw OAuthError.authenticationFailed("Authorization error: \(error)")
        }

        guard let code = callbackResult.code else {
            throw OAuthError.authenticationFailed("No authorization code received")
        }

        Logger.auth.debug("Received authorization code")

        let tokenResponse = try await self.exchangeCodeForTokens(
            code: code,
            redirectURI: redirectURI,
            credentials: credentials
        )

        let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        return OAuthTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? "",
            expiresAt: expiresAt
        )
    }

    private func buildAuthorizationURL(
        credentials: OAuthClientCredentials,
        redirectURI: String,
        state: String
    ) -> URL? {
        var components = URLComponents(string: Self.authorizationEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
        ]
        return components?.url
    }

    private func exchangeCodeForTokens(
        code: String,
        redirectURI: String,
        credentials: OAuthClientCredentials
    ) async throws -> TokenResponse {
        let bodyParams = [
            "code": code,
            "client_id": credentials.clientId,
            "client_secret": credentials.clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
        ]

        return try await self.executeTokenRequest(bodyParams: bodyParams, isRefresh: false)
    }

    private func refreshTokens(_ currentTokens: OAuthTokens) async throws -> OAuthTokens {
        guard let credentials = clientCredentials else { throw OAuthError.notConfigured }

        let bodyParams = [
            "refresh_token": currentTokens.refreshToken,
            "client_id": credentials.clientId,
            "client_secret": credentials.clientSecret,
            "grant_type": "refresh_token",
        ]

        let tokenResponse = try await self.executeTokenRequest(bodyParams: bodyParams, isRefresh: true)
        let newTokens = OAuthTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? currentTokens.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        )

        try await self.keychainManager.saveOAuthData(OAuthData(credentials: credentials, tokens: newTokens))
        return newTokens
    }

    private func executeTokenRequest(bodyParams: [String: String], isRefresh: Bool) async throws -> TokenResponse {
        guard let tokenURL = Self.tokenEndpoint else {
            throw OAuthError.authenticationFailed("Invalid token endpoint")
        }

        let bodyString = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await httpClient.execute(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            let msg = "Invalid response"
            throw isRefresh ? OAuthError.tokenRefreshFailed(msg) : OAuthError.authenticationFailed(msg)
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.auth.error("Token request failed: HTTP \(httpResponse.statusCode): \(errorBody)")
            switch httpResponse.statusCode {
            case 400, 401:
                let msg = "Invalid credentials or tokens"
                throw isRefresh ? OAuthError.tokenRefreshFailed(msg) : OAuthError.authenticationFailed(msg)
            case 500...:
                throw OAuthError.serverError(httpResponse.statusCode, errorBody)
            default:
                let errorMsg = "HTTP \(httpResponse.statusCode): \(errorBody)"
                throw isRefresh
                    ? OAuthError.tokenRefreshFailed(errorMsg)
                    : OAuthError.authenticationFailed(errorMsg)
            }
        }

        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            let errorMsg = "Failed to decode response: \(error.localizedDescription)"
            throw isRefresh ? OAuthError.tokenRefreshFailed(errorMsg) : OAuthError.authenticationFailed(errorMsg)
        }
    }
}

// MARK: - Token Response

/// Response from Google's token endpoint.
private struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - HTTP Client Protocol

/// Protocol for HTTP request execution, enabling dependency injection for testing.
public protocol HTTPClient: Sendable {
    func execute(_ request: URLRequest) async throws -> (Data, URLResponse)
}

/// Default HTTP client using URLSession.
public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func execute(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

// MARK: - Browser Opener Protocol

/// Protocol for opening URLs in browser, enabling dependency injection for testing.
public protocol BrowserOpener: Sendable {
    func open(_ url: URL)
}

#if canImport(AppKit)
    import AppKit

    /// Default browser opener using NSWorkspace.
    public struct SystemBrowserOpener: BrowserOpener {
        public init() {}

        public func open(_ url: URL) {
            NSWorkspace.shared.open(url)
        }
    }
#else
    /// Stub for non-AppKit platforms.
    public struct SystemBrowserOpener: BrowserOpener {
        public init() {}

        public func open(_: URL) {
            // No-op for non-AppKit platforms
        }
    }
#endif

// MARK: - Credential Validation Extension

public extension GoogleOAuthProvider {
    /// Validates credential format before storing.
    func validateCredentials(clientId: String, clientSecret: String) -> ValidationResult {
        if clientId.isEmpty || clientSecret.isEmpty {
            return .invalid("Credentials cannot be empty")
        }
        if !clientId.contains(".apps.googleusercontent.com") {
            return .warning("Client ID doesn't look like a Google OAuth client ID")
        }
        if clientSecret.count < 10 {
            return .warning("Client secret seems unusually short")
        }
        return .valid
    }
}

// MARK: - Error Classification

extension GoogleOAuthProvider {
    /// Classifies a refresh error into an appropriate OAuthError.
    static func classifyRefreshError(_ error: Error) -> OAuthError {
        if let oauthError = error as? OAuthError { return oauthError }
        if error is URLError { return .networkError(error.localizedDescription) }
        return .tokenRefreshFailed(error.localizedDescription)
    }
}
