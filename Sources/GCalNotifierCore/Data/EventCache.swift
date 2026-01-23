import Foundation

/// Actor-based local storage for calendar events.
/// Thread-safe concurrent access with atomic file writes.
public actor EventCache {
    private let fileURL: URL
    private var events: [CalendarEvent]
    private var hasLoaded = false

    /// Creates an EventCache with the default Application Support location.
    public init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = appSupport.appendingPathComponent("gcal-notifier", isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        self.fileURL = appDirectory.appendingPathComponent("events.json")
        self.events = []
    }

    /// Creates an EventCache with a custom file URL (for testing).
    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.events = []
    }

    // MARK: - Core Operations

    /// Saves all events to the cache, replacing any existing content.
    public func save(_ events: [CalendarEvent]) async throws {
        self.events = events
        self.hasLoaded = true
        try await self.persist()
    }

    /// Loads all events from the cache.
    public func load() async throws -> [CalendarEvent] {
        try await self.loadIfNeeded()
        return self.events
    }

    /// Clears all events from the cache.
    public func clear() async throws {
        self.events = []
        self.hasLoaded = true
        try await self.persist()
    }

    // MARK: - Queries

    /// Returns events within the specified time range (inclusive of events that overlap).
    public func events(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        try await self.loadIfNeeded()
        return self.events.filter { event in
            event.startTime < endDate && event.endTime > startDate
        }
    }

    /// Returns the next event starting after the specified date.
    public func nextEvent(after date: Date) async throws -> CalendarEvent? {
        try await self.loadIfNeeded()
        return self.events
            .filter { $0.startTime > date }
            .min { $0.startTime < $1.startTime }
    }

    /// Returns events for a specific calendar.
    public func events(forCalendar calendarId: String) async throws -> [CalendarEvent] {
        try await self.loadIfNeeded()
        return self.events.filter { $0.calendarId == calendarId }
    }

    // MARK: - Updates

    /// Updates an existing event or adds it if not present.
    public func update(_ event: CalendarEvent) async throws {
        try await self.loadIfNeeded()
        if let index = self.events.firstIndex(where: { $0.id == event.id }) {
            self.events[index] = event
        } else {
            self.events.append(event)
        }
        try await self.persist()
    }

    /// Removes an event by its ID.
    public func remove(eventId: String) async throws {
        try await self.loadIfNeeded()
        self.events.removeAll { $0.id == eventId }
        try await self.persist()
    }

    // MARK: - Private Helpers

    private func loadIfNeeded() async throws {
        guard !self.hasLoaded else { return }
        try await self.loadFromDisk()
    }

    private func loadFromDisk() async throws {
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else {
            self.events = []
            self.hasLoaded = true
            return
        }

        let data = try Data(contentsOf: self.fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.events = try decoder.decode([CalendarEvent].self, from: data)
        self.hasLoaded = true
    }

    private func persist() async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self.events)

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
