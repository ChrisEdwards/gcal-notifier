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

// MARK: - CalendarEvent Computed Properties

public extension CalendarEvent {
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
