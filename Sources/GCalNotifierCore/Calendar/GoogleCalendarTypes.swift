import Foundation

/// Response from fetching events, containing events, deleted IDs, and optional sync token.
public struct EventsResponse: Sendable, Equatable {
    public let events: [CalendarEvent]
    public let nextSyncToken: String?
    public let deletedEventIds: [String]

    public init(events: [CalendarEvent], nextSyncToken: String?, deletedEventIds: [String] = []) {
        self.events = events
        self.nextSyncToken = nextSyncToken
        self.deletedEventIds = deletedEventIds
    }
}

/// Basic calendar information.
public struct CalendarInfo: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let summary: String
    public let isPrimary: Bool
    public let accessRole: CalendarAccessRole

    public init(id: String, summary: String, isPrimary: Bool, accessRole: CalendarAccessRole) {
        self.id = id
        self.summary = summary
        self.isPrimary = isPrimary
        self.accessRole = accessRole
    }
}

/// Access role for a calendar.
public enum CalendarAccessRole: String, Codable, Sendable, Equatable {
    case freeBusyReader
    case reader
    case writer
    case owner
}

// MARK: - Access Token Provider Protocol

/// Protocol for providing OAuth access tokens.
public protocol AccessTokenProvider: Sendable {
    func getAccessToken() async throws -> String
}

/// GoogleOAuthProvider already implements getAccessToken, so it conforms to AccessTokenProvider
extension GoogleOAuthProvider: AccessTokenProvider {}
