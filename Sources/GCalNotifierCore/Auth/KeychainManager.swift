import Foundation
import OSLog
import Security

/// OAuth client credentials provided by the user from their Google Cloud project.
public struct OAuthClientCredentials: Codable, Sendable, Equatable {
    public let clientId: String
    public let clientSecret: String

    public init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
}

/// OAuth tokens received from the authorization flow.
public struct OAuthTokens: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Whether the access token has expired.
    public var isExpired: Bool {
        Date() >= self.expiresAt
    }

    /// Time remaining until expiration (negative if already expired).
    public var expiresIn: TimeInterval {
        self.expiresAt.timeIntervalSinceNow
    }
}

/// Combined OAuth data stored as a single Keychain item to minimize password prompts.
public struct OAuthData: Codable, Sendable, Equatable {
    public let credentials: OAuthClientCredentials
    public let tokens: OAuthTokens?

    public init(credentials: OAuthClientCredentials, tokens: OAuthTokens?) {
        self.credentials = credentials
        self.tokens = tokens
    }
}

/// Errors that can occur during Keychain operations.
public enum KeychainError: Error, Equatable, Sendable {
    /// An item was not found in the Keychain.
    case itemNotFound
    /// Failed to encode data for storage.
    case encodingFailed
    /// Failed to decode data from storage.
    case decodingFailed
    /// A Security framework error occurred.
    case securityError(OSStatus)
}

/// Secure storage manager for OAuth credentials and tokens using macOS Keychain.
///
/// `KeychainManager` provides thread-safe access to sensitive authentication data
/// stored in the system Keychain. It uses explicit `kSecAttrService` values to
/// ensure reliable access across debug and release builds.
///
/// ## Usage
/// ```swift
/// let manager = KeychainManager.shared
///
/// // Store client credentials
/// try await manager.saveClientCredentials(credentials)
///
/// // Retrieve tokens
/// if let tokens = try await manager.loadTokens() {
///     // Use tokens
/// }
/// ```
public actor KeychainManager {
    /// Shared singleton instance.
    public static let shared = KeychainManager()

    /// The service identifier for Keychain items.
    private let service: String

    /// The access group for Keychain items (enables persistence across rebuilds).
    private let accessGroup: String?

    /// Keychain account names for different credential types.
    private enum Account: String {
        case clientCredentials = "client_credentials"
        case tokens = "oauth_tokens"
        case combined = "oauth_data"
    }

    /// Creates a new KeychainManager with the specified service identifier.
    /// - Parameters:
    ///   - service: The Keychain service identifier. Defaults to "com.gcal-notifier.auth".
    ///   - accessGroup: Optional Keychain access group. When nil, uses default app access.
    public init(service: String = "com.gcal-notifier.auth", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - Client Credentials

    /// Saves OAuth client credentials to the Keychain.
    /// - Parameter credentials: The client credentials to save.
    /// - Throws: `KeychainError` if the operation fails.
    public func saveClientCredentials(_ credentials: OAuthClientCredentials) throws {
        try self.save(credentials, account: .clientCredentials)
        Logger.auth.debug("Saved client credentials to Keychain")
    }

    /// Loads OAuth client credentials from the Keychain.
    /// - Returns: The stored credentials, or `nil` if not found.
    /// - Throws: `KeychainError` if the operation fails (other than item not found).
    public func loadClientCredentials() throws -> OAuthClientCredentials? {
        try self.load(account: .clientCredentials)
    }

    /// Deletes OAuth client credentials from the Keychain.
    /// - Throws: `KeychainError` if the operation fails.
    public func deleteClientCredentials() throws {
        try self.delete(account: .clientCredentials)
        Logger.auth.debug("Deleted client credentials from Keychain")
    }

    // MARK: - Tokens

    /// Saves OAuth tokens to the Keychain.
    /// - Parameter tokens: The tokens to save.
    /// - Throws: `KeychainError` if the operation fails.
    public func saveTokens(_ tokens: OAuthTokens) throws {
        try self.save(tokens, account: .tokens)
        Logger.auth.debug("Saved OAuth tokens to Keychain")
    }

    /// Loads OAuth tokens from the Keychain.
    /// - Returns: The stored tokens, or `nil` if not found.
    /// - Throws: `KeychainError` if the operation fails (other than item not found).
    public func loadTokens() throws -> OAuthTokens? {
        try self.load(account: .tokens)
    }

    /// Deletes OAuth tokens from the Keychain.
    /// - Throws: `KeychainError` if the operation fails.
    public func deleteTokens() throws {
        try self.delete(account: .tokens)
        Logger.auth.debug("Deleted OAuth tokens from Keychain")
    }

    // MARK: - Combined Data (Single Keychain Access)

    /// Saves combined OAuth data to reduce Keychain access prompts.
    /// - Parameter data: The combined credentials and tokens to save.
    /// - Throws: `KeychainError` if the operation fails.
    public func saveOAuthData(_ data: OAuthData) throws {
        try self.save(data, account: .combined)
        Logger.auth.debug("Saved combined OAuth data to Keychain")
    }

    /// Loads combined OAuth data with a single Keychain access.
    /// Falls back to loading separate items for backwards compatibility.
    /// - Returns: The stored data, or `nil` if not found.
    /// - Throws: `KeychainError` if the operation fails.
    public func loadOAuthData() throws -> OAuthData? {
        // Try loading combined data first
        if let combined: OAuthData = try self.load(account: .combined) {
            return combined
        }

        // Fall back to legacy separate items for backwards compatibility
        guard let credentials: OAuthClientCredentials = try self.load(account: .clientCredentials) else {
            return nil
        }

        let tokens: OAuthTokens? = try self.load(account: .tokens)
        return OAuthData(credentials: credentials, tokens: tokens)
    }

    // MARK: - Bulk Operations

    /// Deletes all authentication data from the Keychain.
    ///
    /// This removes both client credentials and OAuth tokens. Use this
    /// when signing out to ensure complete cleanup.
    ///
    /// - Throws: `KeychainError` if the operation fails.
    public func deleteAll() throws {
        var deletedAny = false

        for account in [Account.clientCredentials, .tokens, .combined] {
            do {
                try self.delete(account: account)
                deletedAny = true
            } catch KeychainError.itemNotFound {
                // Item not found is acceptable during bulk delete
            }
        }

        if deletedAny {
            Logger.auth.debug("Deleted all authentication data from Keychain")
        }
    }

    // MARK: - Private Helpers

    /// Builds the base query dictionary with common attributes.
    private func baseQuery(account: Account) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account.rawValue,
        ]

        // Add access group if specified (enables persistence across rebuilds)
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    /// Saves a Codable value to the Keychain.
    private func save(_ value: some Codable, account: Account) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first to ensure clean overwrite
        SecItemDelete(self.baseQuery(account: account) as CFDictionary)

        // Add new item
        var addQuery = self.baseQuery(account: account)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            Logger.auth.error("Failed to save to Keychain: \(status)")
            throw KeychainError.securityError(status)
        }
    }

    /// Loads a Codable value from the Keychain.
    private func load<T: Codable>(account: Account) throws -> T? {
        var query = self.baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.decodingFailed
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw KeychainError.decodingFailed
            }
        case errSecItemNotFound:
            return nil
        default:
            Logger.auth.error("Failed to load from Keychain: \(status)")
            throw KeychainError.securityError(status)
        }
    }

    /// Deletes an item from the Keychain.
    private func delete(account: Account) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Logger.auth.error("Failed to delete from Keychain: \(status)")
            throw KeychainError.securityError(status)
        }

        if status == errSecItemNotFound {
            throw KeychainError.itemNotFound
        }
    }
}
