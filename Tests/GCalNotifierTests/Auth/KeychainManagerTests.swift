import Foundation
import Testing

@testable import GCalNotifierCore

/// Tests for OAuthClientCredentials data structure.
@Suite("OAuthClientCredentials Tests")
struct OAuthClientCredentialsTests {
    @Test("Initializes with correct values")
    func initialization() {
        let credentials = OAuthClientCredentials(
            clientId: "test-client-id",
            clientSecret: "test-client-secret"
        )

        #expect(credentials.clientId == "test-client-id")
        #expect(credentials.clientSecret == "test-client-secret")
    }

    @Test("Encodes and decodes correctly")
    func codable() throws {
        let original = OAuthClientCredentials(
            clientId: "encode-test-id",
            clientSecret: "encode-test-secret"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OAuthClientCredentials.self, from: encoded)

        #expect(decoded == original)
    }

    @Test("Equals when values match")
    func equatable() {
        let a = OAuthClientCredentials(clientId: "id", clientSecret: "secret")
        let b = OAuthClientCredentials(clientId: "id", clientSecret: "secret")
        let c = OAuthClientCredentials(clientId: "different", clientSecret: "secret")

        #expect(a == b)
        #expect(a != c)
    }
}

/// Tests for OAuthTokens data structure.
@Suite("OAuthTokens Tests")
struct OAuthTokensTests {
    @Test("Initializes with correct values")
    func initialization() {
        let expiresAt = Date().addingTimeInterval(3600)
        let tokens = OAuthTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: expiresAt
        )

        #expect(tokens.accessToken == "access-token")
        #expect(tokens.refreshToken == "refresh-token")
        #expect(tokens.expiresAt == expiresAt)
    }

    @Test("isExpired returns false for future date")
    func notExpired() {
        let tokens = OAuthTokens(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600)
        )

        #expect(tokens.isExpired == false)
        #expect(tokens.expiresIn > 0)
    }

    @Test("isExpired returns true for past date")
    func expired() {
        let tokens = OAuthTokens(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(-60)
        )

        #expect(tokens.isExpired == true)
        #expect(tokens.expiresIn < 0)
    }

    @Test("Encodes and decodes correctly")
    func codable() throws {
        let original = OAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OAuthTokens.self, from: encoded)

        #expect(decoded == original)
    }
}

/// Tests for KeychainError enum.
@Suite("KeychainError Tests")
struct KeychainErrorTests {
    @Test("itemNotFound is equatable")
    func itemNotFoundEquatable() {
        #expect(KeychainError.itemNotFound == KeychainError.itemNotFound)
    }

    @Test("encodingFailed is equatable")
    func encodingFailedEquatable() {
        #expect(KeychainError.encodingFailed == KeychainError.encodingFailed)
    }

    @Test("decodingFailed is equatable")
    func decodingFailedEquatable() {
        #expect(KeychainError.decodingFailed == KeychainError.decodingFailed)
    }

    @Test("securityError with same status is equatable")
    func securityErrorEquatable() {
        #expect(KeychainError.securityError(-25300) == KeychainError.securityError(-25300))
        #expect(KeychainError.securityError(-25300) != KeychainError.securityError(-25308))
    }

    @Test("Different error types are not equal")
    func differentTypesNotEqual() {
        #expect(KeychainError.itemNotFound != KeychainError.encodingFailed)
        #expect(KeychainError.encodingFailed != KeychainError.decodingFailed)
        #expect(KeychainError.decodingFailed != KeychainError.securityError(0))
    }
}

/// KeychainManager tests that interact with the system Keychain.
/// These tests run serially to avoid interference between operations.
@Suite("KeychainManager Tests", .serialized)
struct KeychainManagerTests {
    /// Unique service identifier to isolate test data from production data.
    private let testService = "com.gcal-notifier.auth.tests.\(ProcessInfo.processInfo.processIdentifier)"

    private func createManager() -> KeychainManager {
        KeychainManager(service: self.testService)
    }

    /// Cleans up any leftover test data and returns the manager for use.
    /// This ensures each test starts with a clean slate.
    private func createCleanManager() async -> KeychainManager {
        let manager = KeychainManager(service: self.testService)
        try? await manager.deleteAll()
        return manager
    }

    private func cleanup(_ manager: KeychainManager) async {
        try? await manager.deleteAll()
    }

    @Test("saveClientCredentials stores in Keychain")
    func saveClientCredentials() async throws {
        let manager = self.createManager()
        defer { Task { await cleanup(manager) } }

        let credentials = OAuthClientCredentials(
            clientId: "test-id-123",
            clientSecret: "test-secret-456"
        )

        try await manager.saveClientCredentials(credentials)
        let loaded = try await manager.loadClientCredentials()

        #expect(loaded == credentials)
    }

    @Test("saveTokens stores and retrieves tokens")
    func saveTokens() async throws {
        let manager = self.createManager()
        defer { Task { await cleanup(manager) } }

        let tokens = OAuthTokens(
            accessToken: "access-token-xyz",
            refreshToken: "refresh-token-abc",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try await manager.saveTokens(tokens)
        let loaded = try await manager.loadTokens()

        #expect(loaded == tokens)
    }

    @Test("deleteClientCredentials removes from Keychain")
    func deleteClientCredentials() async throws {
        let manager = self.createManager()
        defer { Task { await cleanup(manager) } }

        let credentials = OAuthClientCredentials(
            clientId: "delete-test-id",
            clientSecret: "delete-test-secret"
        )

        try await manager.saveClientCredentials(credentials)
        try await manager.deleteClientCredentials()
        let loaded = try await manager.loadClientCredentials()

        #expect(loaded == nil)
    }

    @Test("deleteTokens removes from Keychain")
    func deleteTokens() async throws {
        let manager = await self.createCleanManager()
        defer { Task { await cleanup(manager) } }

        let tokens = OAuthTokens(
            accessToken: "delete-token",
            refreshToken: "delete-refresh",
            expiresAt: Date()
        )

        try await manager.saveTokens(tokens)
        try await manager.deleteTokens()
        let loaded = try await manager.loadTokens()

        #expect(loaded == nil)
    }

    @Test("deleteAll clears everything")
    func deleteAll() async throws {
        let manager = self.createManager()
        defer { Task { await cleanup(manager) } }

        let credentials = OAuthClientCredentials(
            clientId: "all-test-id",
            clientSecret: "all-test-secret"
        )
        let tokens = OAuthTokens(
            accessToken: "all-token",
            refreshToken: "all-refresh",
            expiresAt: Date()
        )

        try await manager.saveClientCredentials(credentials)
        try await manager.saveTokens(tokens)
        try await manager.deleteAll()

        let loadedCreds = try await manager.loadClientCredentials()
        let loadedTokens = try await manager.loadTokens()

        #expect(loadedCreds == nil)
        #expect(loadedTokens == nil)
    }

    @Test("loadClientCredentials when not exists returns nil")
    func loadCredentialsNotExists() async throws {
        let manager = self.createManager()
        defer { Task { await cleanup(manager) } }

        let loaded = try await manager.loadClientCredentials()
        #expect(loaded == nil)
    }

    @Test("loadTokens when not exists returns nil")
    func loadTokensNotExists() async throws {
        let manager = self.createManager()
        defer { Task { await cleanup(manager) } }

        let loaded = try await manager.loadTokens()
        #expect(loaded == nil)
    }

    @Test("save overwrites existing credentials")
    func saveOverwritesCredentials() async throws {
        let manager = self.createManager()
        defer { Task { await cleanup(manager) } }

        let original = OAuthClientCredentials(
            clientId: "original-id",
            clientSecret: "original-secret"
        )
        let updated = OAuthClientCredentials(
            clientId: "updated-id",
            clientSecret: "updated-secret"
        )

        try await manager.saveClientCredentials(original)
        try await manager.saveClientCredentials(updated)
        let loaded = try await manager.loadClientCredentials()

        #expect(loaded == updated)
    }

    @Test("save overwrites existing tokens")
    func saveOverwritesTokens() async throws {
        let manager = self.createManager()
        defer { Task { await cleanup(manager) } }

        let original = OAuthTokens(
            accessToken: "original-access",
            refreshToken: "original-refresh",
            expiresAt: Date()
        )
        let updated = OAuthTokens(
            accessToken: "updated-access",
            refreshToken: "updated-refresh",
            expiresAt: Date().addingTimeInterval(7200)
        )

        try await manager.saveTokens(original)
        try await manager.saveTokens(updated)
        let loaded = try await manager.loadTokens()

        #expect(loaded == updated)
    }

    @Test("deleteClientCredentials throws itemNotFound when not exists")
    func deleteCredentialsNotExists() async throws {
        let manager = await self.createCleanManager()
        defer { Task { await cleanup(manager) } }

        await #expect(throws: KeychainError.itemNotFound) {
            try await manager.deleteClientCredentials()
        }
    }

    @Test("deleteTokens throws itemNotFound when not exists")
    func deleteTokensNotExists() async throws {
        let manager = await self.createCleanManager()
        defer { Task { await cleanup(manager) } }

        await #expect(throws: KeychainError.itemNotFound) {
            try await manager.deleteTokens()
        }
    }

    @Test("deleteAll succeeds even when nothing exists")
    func deleteAllWhenEmpty() async throws {
        let manager = self.createManager()

        // Should not throw - deleteAll handles missing items gracefully
        try await manager.deleteAll()
    }

    @Test("credentials and tokens are stored independently")
    func independentStorage() async throws {
        let manager = self.createManager()
        defer { Task { await cleanup(manager) } }

        let credentials = OAuthClientCredentials(
            clientId: "independent-id",
            clientSecret: "independent-secret"
        )
        let tokens = OAuthTokens(
            accessToken: "independent-token",
            refreshToken: "independent-refresh",
            expiresAt: Date()
        )

        try await manager.saveClientCredentials(credentials)
        try await manager.saveTokens(tokens)

        // Delete only credentials
        try await manager.deleteClientCredentials()

        // Tokens should still exist
        let loadedCreds = try await manager.loadClientCredentials()
        let loadedTokens = try await manager.loadTokens()

        #expect(loadedCreds == nil)
        #expect(loadedTokens == tokens)
    }
}
