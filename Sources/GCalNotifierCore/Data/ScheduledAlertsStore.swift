import Foundation

// MARK: - AlertStage

/// Represents the alert stages for meeting reminders.
/// Two-stage alerts: early warning and urgent reminder.
public enum AlertStage: String, Codable, Sendable, Equatable, CaseIterable {
    /// Stage 1: Early warning (default 10 minutes before meeting).
    case stage1

    /// Stage 2: Urgent reminder (default 2 minutes before meeting).
    case stage2

    /// Default offset in minutes for this stage.
    public var defaultMinutesBefore: Int {
        switch self {
        case .stage1: 10
        case .stage2: 2
        }
    }

    /// Human-readable description for display.
    public var displayName: String {
        switch self {
        case .stage1: "Early Warning"
        case .stage2: "Urgent Reminder"
        }
    }
}

// MARK: - ScheduledAlert

/// Represents a scheduled alert that persists across app restarts.
public struct ScheduledAlert: Codable, Sendable, Equatable, Identifiable {
    /// Unique identifier for this scheduled alert.
    public let id: String

    /// The ID of the event this alert is for.
    public let eventId: String

    /// Which alert stage this is (stage1 or stage2).
    public let stage: AlertStage

    /// When this alert should fire.
    public let scheduledFireTime: Date

    /// Number of times this alert has been snoozed.
    public let snoozeCount: Int

    /// Original fire time before any snoozes (nil if never snoozed).
    public let originalFireTime: Date?

    /// Title of the event (for display in alert modal).
    public let eventTitle: String

    /// Start time of the event (for display in alert modal).
    public let eventStartTime: Date

    public init(
        id: String,
        eventId: String,
        stage: AlertStage,
        scheduledFireTime: Date,
        snoozeCount: Int = 0,
        originalFireTime: Date? = nil,
        eventTitle: String,
        eventStartTime: Date
    ) {
        self.id = id
        self.eventId = eventId
        self.stage = stage
        self.scheduledFireTime = scheduledFireTime
        self.snoozeCount = snoozeCount
        self.originalFireTime = originalFireTime
        self.eventTitle = eventTitle
        self.eventStartTime = eventStartTime
    }
}

// MARK: - ScheduledAlert Helpers

public extension ScheduledAlert {
    /// Creates a new alert with updated snooze information.
    func snoozed(until newFireTime: Date) -> ScheduledAlert {
        ScheduledAlert(
            id: self.id,
            eventId: self.eventId,
            stage: self.stage,
            scheduledFireTime: newFireTime,
            snoozeCount: self.snoozeCount + 1,
            originalFireTime: self.originalFireTime ?? self.scheduledFireTime,
            eventTitle: self.eventTitle,
            eventStartTime: self.eventStartTime
        )
    }

    /// Whether this alert has been snoozed at least once.
    var wasSnoozed: Bool {
        self.snoozeCount > 0
    }
}

// MARK: - ScheduledAlertsStore

/// Actor-based persistence for scheduled alerts.
/// Thread-safe concurrent access with atomic file writes.
public actor ScheduledAlertsStore {
    private let fileURL: URL
    private var alerts: [ScheduledAlert]
    private var hasLoaded = false

    /// Creates a ScheduledAlertsStore with the default Application Support location.
    public init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = appSupport.appendingPathComponent("gcal-notifier", isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        self.fileURL = appDirectory.appendingPathComponent("alerts.json")
        self.alerts = []
    }

    /// Creates a ScheduledAlertsStore with a custom file URL (for testing).
    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.alerts = []
    }

    // MARK: - Core Operations

    /// Saves all alerts to storage, replacing any existing content.
    public func save(_ alerts: [ScheduledAlert]) async throws {
        self.alerts = alerts
        self.hasLoaded = true
        try await self.persist()
    }

    /// Loads all alerts from storage.
    public func load() async throws -> [ScheduledAlert] {
        try await self.loadIfNeeded()
        return self.alerts
    }

    // MARK: - Private Helpers

    private func loadIfNeeded() async throws {
        guard !self.hasLoaded else { return }
        try await self.loadFromDisk()
    }

    private func loadFromDisk() async throws {
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else {
            self.alerts = []
            self.hasLoaded = true
            return
        }

        let data = try Data(contentsOf: self.fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.alerts = try decoder.decode([ScheduledAlert].self, from: data)
        self.hasLoaded = true
    }

    private func persist() async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self.alerts)

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
