import Foundation

// MARK: - AppState

/// Internal data structure for persisting application state.
struct AppState: Codable, Sendable {
    var syncTokens: [String: String]
    var lastFullSync: Date?

    init(syncTokens: [String: String] = [:], lastFullSync: Date? = nil) {
        self.syncTokens = syncTokens
        self.lastFullSync = lastFullSync
    }
}

// MARK: - AppStateStore

/// Actor-based persistence for sync tokens and application state.
/// Thread-safe concurrent access with atomic file writes.
public actor AppStateStore {
    private let fileURL: URL
    private var state: AppState

    /// Creates an AppStateStore with the default Application Support location.
    public init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = appSupport.appendingPathComponent("gcal-notifier", isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        self.fileURL = appDirectory.appendingPathComponent("app-state.json")
        self.state = AppState()
    }

    /// Creates an AppStateStore with a custom file URL (for testing).
    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.state = AppState()
    }

    // MARK: - Sync Tokens

    /// Gets the sync token for a specific calendar.
    public func getSyncToken(for calendarId: String) async throws -> String? {
        try await self.loadIfNeeded()
        return self.state.syncTokens[calendarId]
    }

    /// Sets the sync token for a specific calendar.
    public func setSyncToken(_ token: String, for calendarId: String) async throws {
        try await self.loadIfNeeded()
        self.state.syncTokens[calendarId] = token
        try await self.save()
    }

    /// Clears the sync token for a specific calendar.
    public func clearSyncToken(for calendarId: String) async throws {
        try await self.loadIfNeeded()
        self.state.syncTokens.removeValue(forKey: calendarId)
        try await self.save()
    }

    /// Clears all sync tokens.
    public func clearAllSyncTokens() async throws {
        try await self.loadIfNeeded()
        self.state.syncTokens.removeAll()
        try await self.save()
    }

    // MARK: - Last Full Sync

    /// Gets the timestamp of the last full sync.
    public func getLastFullSync() async throws -> Date? {
        try await self.loadIfNeeded()
        return self.state.lastFullSync
    }

    /// Sets the timestamp of the last full sync.
    public func setLastFullSync(_ date: Date) async throws {
        try await self.loadIfNeeded()
        self.state.lastFullSync = date
        try await self.save()
    }

    // MARK: - Private Helpers

    private var hasLoaded = false

    private func loadIfNeeded() async throws {
        guard !self.hasLoaded else { return }
        try await self.load()
    }

    private func load() async throws {
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else {
            self.state = AppState()
            self.hasLoaded = true
            return
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.state = try decoder.decode(AppState.self, from: data)
        self.hasLoaded = true
    }

    private func save() async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self.state)

        // Atomic write: write to temp file, then rename
        let tempURL = self.fileURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".tmp")
        try data.write(to: tempURL, options: .atomic)

        // Move to final location
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: self.fileURL.path) {
            try fileManager.removeItem(at: self.fileURL)
        }
        try fileManager.moveItem(at: tempURL, to: self.fileURL)
    }
}
