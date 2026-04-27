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

// MARK: - AlertNotificationPayload

/// Sound behavior for a scheduled OS notification.
public enum AlertNotificationSoundBehavior: String, Codable, Sendable, Equatable {
    case none
    case defaultSound = "default"
}

/// Urgency metadata for a scheduled OS notification.
public enum AlertNotificationUrgency: String, Codable, Sendable, Equatable {
    case passive
    case active
    case timeSensitive
}

/// User-facing notification content and OS delivery metadata captured at schedule time.
public struct AlertNotificationPayload: Codable, Sendable, Equatable {
    public static let modalTimingCategoryIdentifier = "MEETING_ALERT"
    public static let stage1CategoryIdentifier = "STAGE1_MEETING_ALERT"
    public static let stage2CategoryIdentifier = "STAGE2_MEETING_ALERT"

    public let title: String
    public let body: String
    public let categoryIdentifier: String
    public let soundBehavior: AlertNotificationSoundBehavior
    public let urgency: AlertNotificationUrgency

    public init(
        title: String,
        body: String,
        categoryIdentifier: String,
        soundBehavior: AlertNotificationSoundBehavior,
        urgency: AlertNotificationUrgency
    ) {
        self.title = title
        self.body = body
        self.categoryIdentifier = categoryIdentifier
        self.soundBehavior = soundBehavior
        self.urgency = urgency
    }

    public static func make(
        eventTitle: String,
        eventStartTime: Date,
        stage: AlertStage
    ) -> AlertNotificationPayload {
        let body = Self.body(eventTitle: eventTitle, eventStartTime: eventStartTime)

        switch stage {
        case .stage1:
            return AlertNotificationPayload(
                title: "Upcoming meeting",
                body: body,
                categoryIdentifier: Self.stage1CategoryIdentifier,
                soundBehavior: .none,
                urgency: .active
            )
        case .stage2:
            return AlertNotificationPayload(
                title: "Meeting starts soon",
                body: body,
                categoryIdentifier: Self.stage2CategoryIdentifier,
                soundBehavior: .defaultSound,
                urgency: .timeSensitive
            )
        }
    }

    private static func body(eventTitle: String, eventStartTime: Date) -> String {
        let startTime = eventStartTime.formatted(date: .omitted, time: .shortened)
        return "\(eventTitle) starts at \(startTime)"
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

    /// End time of the event captured at schedule time.
    public let eventEndTime: Date

    /// Primary meeting join URL captured at schedule time.
    public let joinURL: URL?

    /// Google Calendar event URL captured at schedule time.
    public let calendarURL: URL?

    /// Notification content and OS delivery metadata captured at schedule time.
    public let notificationPayload: AlertNotificationPayload

    public init(
        id: String,
        eventId: String,
        stage: AlertStage,
        scheduledFireTime: Date,
        snoozeCount: Int = 0,
        originalFireTime: Date? = nil,
        eventTitle: String,
        eventStartTime: Date,
        eventEndTime: Date? = nil,
        joinURL: URL? = nil,
        calendarURL: URL? = nil,
        notificationPayload: AlertNotificationPayload? = nil
    ) {
        self.id = id
        self.eventId = eventId
        self.stage = stage
        self.scheduledFireTime = scheduledFireTime
        self.snoozeCount = snoozeCount
        self.originalFireTime = originalFireTime
        self.eventTitle = eventTitle
        self.eventStartTime = eventStartTime
        self.eventEndTime = eventEndTime ?? eventStartTime
        self.joinURL = joinURL
        self.calendarURL = calendarURL
        self.notificationPayload = notificationPayload ?? AlertNotificationPayload.make(
            eventTitle: eventTitle,
            eventStartTime: eventStartTime,
            stage: stage
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case eventId
        case stage
        case scheduledFireTime
        case snoozeCount
        case originalFireTime
        case eventTitle
        case eventStartTime
        case eventEndTime
        case joinURL
        case calendarURL
        case notificationPayload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let eventId = try container.decode(String.self, forKey: .eventId)
        let stage = try container.decode(AlertStage.self, forKey: .stage)
        let scheduledFireTime = try container.decode(Date.self, forKey: .scheduledFireTime)
        let snoozeCount = try container.decode(Int.self, forKey: .snoozeCount)
        let originalFireTime = try container.decodeIfPresent(Date.self, forKey: .originalFireTime)
        let eventTitle = try container.decode(String.self, forKey: .eventTitle)
        let eventStartTime = try container.decode(Date.self, forKey: .eventStartTime)
        let notificationPayload = try container.decodeIfPresent(
            AlertNotificationPayload.self,
            forKey: .notificationPayload
        )
        let eventEndTime = try container.decodeIfPresent(Date.self, forKey: .eventEndTime)
        let joinURL = try container.decodeIfPresent(URL.self, forKey: .joinURL)
        let calendarURL = try container.decodeIfPresent(URL.self, forKey: .calendarURL)

        self.init(
            id: id,
            eventId: eventId,
            stage: stage,
            scheduledFireTime: scheduledFireTime,
            snoozeCount: snoozeCount,
            originalFireTime: originalFireTime,
            eventTitle: eventTitle,
            eventStartTime: eventStartTime,
            eventEndTime: eventEndTime,
            joinURL: joinURL,
            calendarURL: calendarURL,
            notificationPayload: notificationPayload
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.eventId, forKey: .eventId)
        try container.encode(self.stage, forKey: .stage)
        try container.encode(self.scheduledFireTime, forKey: .scheduledFireTime)
        try container.encode(self.snoozeCount, forKey: .snoozeCount)
        try container.encodeIfPresent(self.originalFireTime, forKey: .originalFireTime)
        try container.encode(self.eventTitle, forKey: .eventTitle)
        try container.encode(self.eventStartTime, forKey: .eventStartTime)
        try container.encode(self.eventEndTime, forKey: .eventEndTime)
        try container.encodeIfPresent(self.joinURL, forKey: .joinURL)
        try container.encodeIfPresent(self.calendarURL, forKey: .calendarURL)
        try container.encode(self.notificationPayload, forKey: .notificationPayload)
    }
}

// MARK: - ScheduledAlert Helpers

public extension ScheduledAlert {
    /// Calendar event synthesized from the persisted snapshot for cache-independent modal display.
    var fallbackCalendarEvent: CalendarEvent {
        let eventIdentity = self.eventIdentity
        let meetingLinks = self.joinURL.map { [MeetingLink(url: $0)] } ?? []

        return CalendarEvent(
            id: eventIdentity.eventId,
            calendarId: eventIdentity.calendarId,
            title: self.eventTitle,
            startTime: self.eventStartTime,
            endTime: self.eventEndTime,
            isAllDay: false,
            location: nil,
            meetingLinks: meetingLinks,
            isOrganizer: false,
            attendeeCount: 0,
            responseStatus: .accepted,
            htmlLink: self.calendarURL
        )
    }

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
            eventStartTime: self.eventStartTime,
            eventEndTime: self.eventEndTime,
            joinURL: self.joinURL,
            calendarURL: self.calendarURL,
            notificationPayload: self.notificationPayload
        )
    }

    func replacingSnapshot(with alert: ScheduledAlert) -> ScheduledAlert {
        ScheduledAlert(
            id: self.id,
            eventId: self.eventId,
            stage: self.stage,
            scheduledFireTime: self.scheduledFireTime,
            snoozeCount: self.snoozeCount,
            originalFireTime: self.originalFireTime,
            eventTitle: alert.eventTitle,
            eventStartTime: alert.eventStartTime,
            eventEndTime: alert.eventEndTime,
            joinURL: alert.joinURL,
            calendarURL: alert.calendarURL,
            notificationPayload: alert.notificationPayload
        )
    }

    /// Whether this alert has been snoozed at least once.
    var wasSnoozed: Bool {
        self.snoozeCount > 0
    }

    private var eventIdentity: (calendarId: String, eventId: String) {
        guard let separatorRange = self.eventId.range(of: "::") else {
            return ("", self.eventId)
        }

        return (
            String(self.eventId[..<separatorRange.lowerBound]),
            String(self.eventId[separatorRange.upperBound...])
        )
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
