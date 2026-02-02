import Foundation
import Testing
@testable import GCalNotifierCore

// MARK: - Test Helpers

/// Creates a temporary file URL for test isolation.
private func makeTempFileURL() -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let testDir = tempDir.appendingPathComponent("AppStateStoreTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    return testDir.appendingPathComponent("app-state.json")
}

/// Cleans up a temporary test directory.
private func cleanupTempDir(_ url: URL) {
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.removeItem(at: dir)
}

// MARK: - Sync Token Tests

@Suite("AppStateStore Sync Token Tests")
struct AppStateStoreSyncTokenTests {
    @Test("Save and load sync token for single calendar")
    func syncTokenSaveAndLoad() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = AppStateStore(fileURL: fileURL)
        let calendarId = "primary"
        let token = "sync-token-123"

        try await store.setSyncToken(token, for: calendarId)
        let retrieved = try await store.getSyncToken(for: calendarId)

        #expect(retrieved == token)
    }

    @Test("Get sync token returns nil for unknown calendar")
    func syncTokenNilForUnknown() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = AppStateStore(fileURL: fileURL)
        let retrieved = try await store.getSyncToken(for: "unknown-calendar")

        #expect(retrieved == nil)
    }

    @Test("Multiple calendars have independent sync tokens")
    func syncTokenMultipleCalendars() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = AppStateStore(fileURL: fileURL)

        try await store.setSyncToken("token-primary", for: "primary")
        try await store.setSyncToken("token-work", for: "work@example.com")
        try await store.setSyncToken("token-personal", for: "personal@example.com")

        let primary = try await store.getSyncToken(for: "primary")
        let work = try await store.getSyncToken(for: "work@example.com")
        let personal = try await store.getSyncToken(for: "personal@example.com")

        #expect(primary == "token-primary")
        #expect(work == "token-work")
        #expect(personal == "token-personal")
    }

    @Test("Clear sync token for single calendar")
    func syncTokenClear() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = AppStateStore(fileURL: fileURL)

        try await store.setSyncToken("token-primary", for: "primary")
        try await store.setSyncToken("token-work", for: "work@example.com")

        try await store.clearSyncToken(for: "primary")

        let primary = try await store.getSyncToken(for: "primary")
        let work = try await store.getSyncToken(for: "work@example.com")

        #expect(primary == nil)
        #expect(work == "token-work")
    }

    @Test("Clear all sync tokens")
    func syncTokenClearAll() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = AppStateStore(fileURL: fileURL)

        try await store.setSyncToken("token-1", for: "calendar-1")
        try await store.setSyncToken("token-2", for: "calendar-2")
        try await store.setSyncToken("token-3", for: "calendar-3")

        try await store.clearAllSyncTokens()

        let token1 = try await store.getSyncToken(for: "calendar-1")
        let token2 = try await store.getSyncToken(for: "calendar-2")
        let token3 = try await store.getSyncToken(for: "calendar-3")

        #expect(token1 == nil)
        #expect(token2 == nil)
        #expect(token3 == nil)
    }

    @Test("Update existing sync token")
    func syncTokenUpdate() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = AppStateStore(fileURL: fileURL)

        try await store.setSyncToken("old-token", for: "primary")
        try await store.setSyncToken("new-token", for: "primary")

        let retrieved = try await store.getSyncToken(for: "primary")
        #expect(retrieved == "new-token")
    }
}

// MARK: - Last Full Sync Tests

@Suite("AppStateStore Last Full Sync Tests")
struct AppStateStoreLastFullSyncTests {
    @Test("Save and load last full sync date")
    func lastFullSyncSaveAndLoad() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = AppStateStore(fileURL: fileURL)
        let syncDate = Date(timeIntervalSince1970: 1_700_000_000)

        try await store.setLastFullSync(syncDate)
        let retrieved = try await store.getLastFullSync()

        #expect(retrieved == syncDate)
    }

    @Test("Last full sync returns nil when never set")
    func lastFullSyncNilWhenUnset() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = AppStateStore(fileURL: fileURL)
        let retrieved = try await store.getLastFullSync()

        #expect(retrieved == nil)
    }

    @Test("Last full sync can be updated")
    func lastFullSyncUpdate() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = AppStateStore(fileURL: fileURL)
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = Date(timeIntervalSince1970: 1_700_100_000)

        try await store.setLastFullSync(oldDate)
        try await store.setLastFullSync(newDate)

        let retrieved = try await store.getLastFullSync()
        #expect(retrieved == newDate)
    }
}

// MARK: - Persistence Tests

@Suite("AppStateStore Persistence Tests")
struct AppStateStorePersistenceTests {
    @Test("Data survives reload with new store instance")
    func persistenceSurvivesReload() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let syncDate = Date(timeIntervalSince1970: 1_700_000_000)

        // First store instance
        do {
            let store = AppStateStore(fileURL: fileURL)
            try await store.setSyncToken("persistent-token", for: "primary")
            try await store.setLastFullSync(syncDate)
        }

        // New store instance loading from same file
        do {
            let store = AppStateStore(fileURL: fileURL)
            let token = try await store.getSyncToken(for: "primary")
            let lastSync = try await store.getLastFullSync()

            #expect(token == "persistent-token")
            #expect(lastSync == syncDate)
        }
    }

    @Test("Empty file handled gracefully")
    func persistenceEmptyFileHandled() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        // Create parent directory
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let store = AppStateStore(fileURL: fileURL)

        // Should not throw, should return nil/empty
        let token = try await store.getSyncToken(for: "any")
        let lastSync = try await store.getLastFullSync()

        #expect(token == nil)
        #expect(lastSync == nil)
    }

    @Test("Modifications persist across operations")
    func persistenceModificationsAccumulate() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = AppStateStore(fileURL: fileURL)
        let syncDate = Date(timeIntervalSince1970: 1_700_000_000)

        // Multiple operations
        try await store.setSyncToken("token-1", for: "calendar-1")
        try await store.setSyncToken("token-2", for: "calendar-2")
        try await store.setLastFullSync(syncDate)
        try await store.clearSyncToken(for: "calendar-1")

        // Verify final state
        let token1 = try await store.getSyncToken(for: "calendar-1")
        let token2 = try await store.getSyncToken(for: "calendar-2")
        let lastSync = try await store.getLastFullSync()

        #expect(token1 == nil)
        #expect(token2 == "token-2")
        #expect(lastSync == syncDate)

        // Reload and verify
        let store2 = AppStateStore(fileURL: fileURL)
        let token1Reloaded = try await store2.getSyncToken(for: "calendar-1")
        let token2Reloaded = try await store2.getSyncToken(for: "calendar-2")
        let lastSyncReloaded = try await store2.getLastFullSync()

        #expect(token1Reloaded == nil)
        #expect(token2Reloaded == "token-2")
        #expect(lastSyncReloaded == syncDate)
    }
}

// MARK: - Combined State Tests

@Suite("AppStateStore Combined State Tests")
struct AppStateStoreCombinedStateTests {
    @Test("Sync tokens and last full sync coexist")
    func combinedState() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = AppStateStore(fileURL: fileURL)
        let syncDate = Date(timeIntervalSince1970: 1_700_000_000)

        try await store.setSyncToken("token-primary", for: "primary")
        try await store.setSyncToken("token-work", for: "work")
        try await store.setLastFullSync(syncDate)

        let primaryToken = try await store.getSyncToken(for: "primary")
        let workToken = try await store.getSyncToken(for: "work")
        let lastSync = try await store.getLastFullSync()

        #expect(primaryToken == "token-primary")
        #expect(workToken == "token-work")
        #expect(lastSync == syncDate)
    }

    @Test("Clear all tokens does not affect last full sync")
    func clearTokensPreservesLastSync() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = AppStateStore(fileURL: fileURL)
        let syncDate = Date(timeIntervalSince1970: 1_700_000_000)

        try await store.setSyncToken("token-1", for: "calendar-1")
        try await store.setLastFullSync(syncDate)
        try await store.clearAllSyncTokens()

        let token = try await store.getSyncToken(for: "calendar-1")
        let lastSync = try await store.getLastFullSync()

        #expect(token == nil)
        #expect(lastSync == syncDate)
    }
}
