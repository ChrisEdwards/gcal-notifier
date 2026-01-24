import Foundation

// MARK: - ResponseStatus

/// Represents the user's response status to a calendar event.
public enum ResponseStatus: String, Codable, Sendable, Equatable {
    case accepted
    case declined
    case tentative
    case needsAction

    /// Priority value for event prioritization when multiple meetings conflict.
    /// Higher values indicate higher priority.
    public var priority: Int {
        switch self {
        case .accepted: 3
        case .tentative: 2
        case .needsAction: 1
        case .declined: 0
        }
    }
}

// MARK: - MeetingPlatform

/// Represents known video conferencing platforms.
public enum MeetingPlatform: String, Codable, Sendable, Equatable {
    case googleMeet
    case zoom
    case teams
    case webex
    case slackHuddle
    case unknown

    /// Detects the meeting platform from a URL.
    public static func detect(from url: URL) -> MeetingPlatform {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()

        // Google Meet
        if host.contains("meet.google.com") {
            return .googleMeet
        }

        // Zoom
        if host.contains("zoom.us") || host.contains("zoomgov.com") {
            return .zoom
        }

        // Microsoft Teams
        if host.contains("teams.microsoft.com") || host.contains("teams.live.com") {
            return .teams
        }

        // Cisco Webex
        if host.contains("webex.com") {
            return .webex
        }

        // Slack Huddle
        if host.contains("slack.com"), path.contains("huddle") {
            return .slackHuddle
        }

        return .unknown
    }
}

// MARK: - MeetingLink

/// Represents a meeting link extracted from a calendar event.
public struct MeetingLink: Codable, Sendable, Equatable {
    public let url: URL
    public let platform: MeetingPlatform

    public init(url: URL, platform: MeetingPlatform? = nil) {
        self.url = url
        self.platform = platform ?? MeetingPlatform.detect(from: url)
    }
}

// MARK: - CalendarEvent

/// Represents a calendar event with all relevant data for display and alerting.
public struct CalendarEvent: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let calendarId: String
    public let title: String
    public let startTime: Date
    public let endTime: Date
    public let isAllDay: Bool
    public let location: String?
    public let meetingLinks: [MeetingLink]
    public let isOrganizer: Bool
    public let attendeeCount: Int
    public let responseStatus: ResponseStatus

    public init(
        id: String,
        calendarId: String,
        title: String,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool,
        location: String?,
        meetingLinks: [MeetingLink],
        isOrganizer: Bool,
        attendeeCount: Int,
        responseStatus: ResponseStatus
    ) {
        self.id = id
        self.calendarId = calendarId
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
        self.location = location
        self.meetingLinks = meetingLinks
        self.isOrganizer = isOrganizer
        self.attendeeCount = attendeeCount
        self.responseStatus = responseStatus
    }
}

// MARK: - Back-to-Back Detection

public extension CalendarEvent {
    /// Maximum gap in seconds for events to be considered back-to-back (5 minutes).
    static let backToBackThreshold: TimeInterval = 5 * 60

    /// Whether this meeting is back-to-back with another (next meeting starts within 5 minutes of this ending).
    /// - Parameter other: The next event to check against.
    /// - Returns: `true` if the other event starts within 5 minutes after this one ends.
    func isBackToBack(with other: CalendarEvent) -> Bool {
        let gap = other.startTime.timeIntervalSince(self.endTime)
        return gap >= 0 && gap <= Self.backToBackThreshold
    }
}

// MARK: - CalendarEvent Computed Properties

public extension CalendarEvent {
    /// Unique identifier scoped to the calendar (prevents collisions across calendars).
    var qualifiedId: String {
        "\(self.calendarId)::\(self.id)"
    }

    /// Alert identifier for a given stage, scoped to the calendar.
    func alertIdentifier(for stage: AlertStage) -> String {
        "\(self.qualifiedId)-\(stage.rawValue)"
    }

    /// Whether this event should trigger an alert.
    /// Events with meeting links should alert (except all-day events).
    var shouldAlert: Bool {
        guard !self.isAllDay else { return false }
        return !self.meetingLinks.isEmpty
    }

    /// The primary meeting URL, if any (first meeting link).
    var primaryMeetingURL: URL? {
        self.meetingLinks.first?.url
    }

    /// Whether the user is currently "in" this meeting (meeting is in progress).
    /// - Parameter now: The current time (defaults to now).
    /// - Returns: `true` if now is between startTime and endTime.
    func isInProgress(at now: Date = Date()) -> Bool {
        self.startTime <= now && now < self.endTime
    }

    /// Whether this event has a video meeting link.
    var hasVideoLink: Bool {
        !self.meetingLinks.isEmpty
    }

    /// A context line describing the event for display in alerts.
    var contextLine: String {
        // Special case: Interview (keyword in title)
        if self.title.localizedCaseInsensitiveContains("interview") {
            return "👤 Interview with candidate"
        }

        // Special case: 1:1 meeting (exactly 2 attendees and not organizer)
        if self.attendeeCount == 2, !self.isOrganizer {
            return "👤 1:1 with colleague"
        }

        // Standard: show attendee count and your role
        let attendeeText = "👥 \(attendeeCount) attendee\(attendeeCount == 1 ? "" : "s")"

        let roleText = if self.isOrganizer {
            "You're organizing"
        } else {
            switch self.responseStatus {
            case .accepted:
                "Accepted"
            case .tentative:
                "Tentative ⚠️"
            case .needsAction:
                "Not responded"
            case .declined:
                "Declined"
            }
        }

        return "\(attendeeText) · \(roleText)"
    }
}

// MARK: - BackToBackState

/// Represents the current back-to-back meeting state.
public struct BackToBackState: Sendable, Equatable {
    /// The current meeting the user is in (nil if not in a meeting).
    public let currentMeeting: CalendarEvent?

    /// The next meeting that is back-to-back with the current one (nil if none).
    public let nextBackToBackMeeting: CalendarEvent?

    /// Whether the user is currently in a back-to-back situation.
    public var isBackToBack: Bool {
        self.currentMeeting != nil && self.nextBackToBackMeeting != nil
    }

    public init(currentMeeting: CalendarEvent?, nextBackToBackMeeting: CalendarEvent?) {
        self.currentMeeting = currentMeeting
        self.nextBackToBackMeeting = nextBackToBackMeeting
    }

    /// Creates an empty state (not in any meeting).
    public static let none = BackToBackState(currentMeeting: nil, nextBackToBackMeeting: nil)
}

// MARK: - BackToBackState Detection

public extension BackToBackState {
    /// Detects the current back-to-back state from a list of events.
    /// - Parameters:
    ///   - events: All calendar events to consider.
    ///   - now: The current time (defaults to now).
    /// - Returns: The detected back-to-back state.
    static func detect(from events: [CalendarEvent], now: Date = Date()) -> BackToBackState {
        // Find the current meeting (user is in a meeting with video link)
        let currentMeeting = events.first { event in
            event.isInProgress(at: now) && event.hasVideoLink
        }

        guard let current = currentMeeting else {
            return .none
        }

        // Find the next meeting that would be back-to-back
        let nextBackToBack = events
            .filter { event in
                event.startTime > now && event.hasVideoLink && event.qualifiedId != current.qualifiedId
            }
            .sorted { $0.startTime < $1.startTime }
            .first { current.isBackToBack(with: $0) }

        return BackToBackState(currentMeeting: current, nextBackToBackMeeting: nextBackToBack)
    }

    /// Minutes until the current meeting ends.
    var minutesUntilCurrentEnds: Int? {
        guard let current = currentMeeting else { return nil }
        let interval = current.endTime.timeIntervalSinceNow
        return max(0, Int(interval / 60))
    }

    /// Minutes until the next back-to-back meeting starts.
    var minutesUntilNextStarts: Int? {
        guard let next = nextBackToBackMeeting else { return nil }
        let interval = next.startTime.timeIntervalSinceNow
        return max(0, Int(interval / 60))
    }
}
