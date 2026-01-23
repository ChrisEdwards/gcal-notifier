import Foundation
import OSLog

/// HTTP client for Google Calendar API operations.
///
/// `GoogleCalendarClient` provides a type-safe interface for fetching calendars and events
/// from the Google Calendar API. It handles token injection, error mapping, and response parsing.
///
/// ## Usage
/// ```swift
/// let client = GoogleCalendarClient(httpClient: URLSessionHTTPClient(), tokenProvider: oauthProvider)
/// let calendars = try await client.fetchCalendarList()
/// let events = try await client.fetchEvents(calendarId: "primary", from: now, to: tomorrow)
/// ```
public actor GoogleCalendarClient {
    // MARK: - Constants

    private static let baseURL = "https://www.googleapis.com/calendar/v3"
    private static let calendarListEndpoint = "/users/me/calendarList"
    private static let eventsEndpoint = "/calendars/{calendarId}/events"

    // MARK: - Dependencies

    private let httpClient: HTTPClient
    private let tokenProvider: AccessTokenProvider

    // MARK: - Initialization

    /// Creates a GoogleCalendarClient with an HTTP client and token provider.
    /// - Parameters:
    ///   - httpClient: The HTTP client for making network requests.
    ///   - tokenProvider: Provider for OAuth access tokens.
    public init(httpClient: HTTPClient, tokenProvider: AccessTokenProvider) {
        self.httpClient = httpClient
        self.tokenProvider = tokenProvider
    }

    // MARK: - Public API

    /// Fetches the list of calendars for the authenticated user.
    /// - Returns: Array of calendar information.
    /// - Throws: `CalendarError` for API or network failures.
    public func fetchCalendarList() async throws -> [CalendarInfo] {
        guard let url = URL(string: Self.baseURL + Self.calendarListEndpoint) else {
            throw CalendarError.invalidRequest("Failed to construct calendar list URL")
        }
        let request = try await buildRequest(url: url)
        let data = try await executeRequest(request)

        do {
            let response = try JSONDecoder().decode(CalendarListResponse.self, from: data)
            return response.items.map { item in
                CalendarInfo(
                    id: item.id,
                    summary: item.summary,
                    isPrimary: item.primary ?? false,
                    accessRole: CalendarAccessRole(rawValue: item.accessRole) ?? .reader
                )
            }
        } catch {
            throw CalendarError.parsingError("Failed to parse calendar list: \(error.localizedDescription)")
        }
    }

    /// Fetches events from a calendar.
    /// - Parameters:
    ///   - calendarId: The calendar ID (use "primary" for the user's primary calendar).
    ///   - from: Start time for event range (optional, used for full sync).
    ///   - to: End time for event range (optional, used for full sync).
    ///   - syncToken: Token for incremental sync (optional).
    ///   - timeZone: Time zone identifier for the response (defaults to system time zone).
    /// - Returns: Events response with events and next sync token.
    /// - Throws: `CalendarError` for API or network failures.
    public func fetchEvents(
        calendarId: String,
        from: Date? = nil,
        to: Date? = nil,
        syncToken: String? = nil,
        timeZone: TimeZone = .current
    ) async throws -> EventsResponse {
        let endpoint = Self.eventsEndpoint.replacingOccurrences(of: "{calendarId}", with: calendarId)
        guard var components = URLComponents(string: Self.baseURL + endpoint) else {
            throw CalendarError.invalidRequest("Failed to construct events URL")
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "timeZone", value: timeZone.identifier),
        ]

        if let syncToken {
            queryItems.append(URLQueryItem(name: "syncToken", value: syncToken))
        } else {
            queryItems.append(URLQueryItem(name: "singleEvents", value: "true"))
            queryItems.append(URLQueryItem(name: "orderBy", value: "startTime"))
            if let from {
                queryItems.append(URLQueryItem(name: "timeMin", value: self.formatISO8601(from)))
            }
            if let to {
                queryItems.append(URLQueryItem(name: "timeMax", value: self.formatISO8601(to)))
            }
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw CalendarError.invalidRequest("Failed to construct events URL")
        }

        let request = try await buildRequest(url: url)
        let data = try await executeRequest(request, calendarId: calendarId)

        do {
            let response = try JSONDecoder.calendarDecoder.decode(GoogleEventsResponse.self, from: data)
            let events = response.items.compactMap { item in
                self.parseEvent(from: item, calendarId: calendarId)
            }
            return EventsResponse(events: events, nextSyncToken: response.nextSyncToken)
        } catch {
            throw CalendarError.parsingError("Failed to parse events: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    private func buildRequest(url: URL) async throws -> URLRequest {
        let accessToken: String
        do {
            accessToken = try await self.tokenProvider.getAccessToken()
        } catch {
            throw CalendarError.authenticationRequired
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func executeRequest(_ request: URLRequest, calendarId: String? = nil) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await self.httpClient.execute(request)
        } catch let urlError as URLError {
            throw mapURLError(urlError)
        } catch {
            throw CalendarError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarError.networkError("Invalid response type")
        }

        if let error = CalendarError.from(
            httpStatusCode: httpResponse.statusCode,
            message: extractErrorMessage(from: data),
            calendarId: calendarId
        ) {
            if httpResponse.statusCode == 403, self.isRateLimitError(from: data) {
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
                throw CalendarError.rateLimited(retryAfter: retryAfter)
            }
            throw error
        }

        return data
    }

    private func mapURLError(_ error: URLError) -> CalendarError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            .offline
        case .timedOut:
            .timeout
        default:
            .networkError(error.localizedDescription)
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let errorResponse = try? JSONDecoder().decode(GoogleErrorResponse.self, from: data) else {
            return nil
        }
        return errorResponse.error.message
    }

    private func isRateLimitError(from data: Data) -> Bool {
        guard let errorInfo = try? JSONDecoder().decode(GoogleErrorResponse.self, from: data) else {
            return false
        }
        return errorInfo.error.errors.contains { $0.reason == "rateLimitExceeded" }
    }

    private func formatISO8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func parseEvent(from item: GoogleEventItem, calendarId: String) -> CalendarEvent? {
        guard let startTime = parseEventTime(item.start),
              let endTime = parseEventTime(item.end)
        else {
            return nil
        }

        let isAllDay = item.start?.date != nil
        let meetingLinks = self.extractMeetingLinks(from: item)
        let responseStatus = self.parseResponseStatus(from: item)
        let attendeeCount = item.attendees?.count ?? 1

        return CalendarEvent(
            id: item.id,
            calendarId: calendarId,
            title: item.summary ?? "(No title)",
            startTime: startTime,
            endTime: endTime,
            isAllDay: isAllDay,
            location: item.location,
            meetingLinks: meetingLinks,
            isOrganizer: item.organizer?.self_ ?? false,
            attendeeCount: attendeeCount,
            responseStatus: responseStatus
        )
    }

    private func parseEventTime(_ time: GoogleEventTime?) -> Date? {
        guard let time else { return nil }

        if let dateTimeString = time.dateTime {
            return ISO8601DateFormatter().date(from: dateTimeString)
        }

        if let dateString = time.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: dateString)
        }

        return nil
    }

    private func extractMeetingLinks(from item: GoogleEventItem) -> [MeetingLink] {
        var links: [MeetingLink] = []
        var seenURLs: Set<String> = []

        self.addConferenceLinks(from: item.conferenceData, to: &links, seenURLs: &seenURLs)
        self.addLinkIfNew(item.hangoutLink, to: &links, seenURLs: &seenURLs)
        if let location = item.location { self.addExtractedURL(from: location, to: &links, seenURLs: &seenURLs) }
        if let desc = item.description { self.addExtractedURLs(from: desc, to: &links, seenURLs: &seenURLs) }

        return links
    }

    private func addConferenceLinks(
        from data: GoogleConferenceData?,
        to links: inout [MeetingLink],
        seenURLs: inout Set<String>
    ) {
        guard let data else { return }
        for entryPoint in data.entryPoints ?? [] where entryPoint.entryPointType == "video" {
            addLinkIfNew(entryPoint.uri, to: &links, seenURLs: &seenURLs)
        }
    }

    private func addLinkIfNew(_ urlString: String?, to links: inout [MeetingLink], seenURLs: inout Set<String>) {
        guard let urlString, let url = URL(string: urlString), !seenURLs.contains(urlString) else { return }
        links.append(MeetingLink(url: url))
        seenURLs.insert(urlString)
    }

    private func addExtractedURL(from text: String, to links: inout [MeetingLink], seenURLs: inout Set<String>) {
        guard let url = extractURL(from: text), !seenURLs.contains(url.absoluteString) else { return }
        links.append(MeetingLink(url: url))
        seenURLs.insert(url.absoluteString)
    }

    private func addExtractedURLs(from text: String, to links: inout [MeetingLink], seenURLs: inout Set<String>) {
        for url in self.extractMeetingURLs(from: text) where !seenURLs.contains(url.absoluteString) {
            links.append(MeetingLink(url: url))
            seenURLs.insert(url.absoluteString)
        }
    }

    private func extractURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, range: range)

        for match in matches {
            if let url = match.url, isMeetingURL(url) {
                return url
            }
        }

        return nil
    }

    private func extractMeetingURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, range: range)

        return matches.compactMap { match -> URL? in
            guard let url = match.url, isMeetingURL(url) else { return nil }
            return url
        }
    }

    private func isMeetingURL(_ url: URL) -> Bool {
        MeetingPlatform.detect(from: url) != .unknown
    }

    private func parseResponseStatus(from item: GoogleEventItem) -> ResponseStatus {
        guard let attendees = item.attendees else {
            return .accepted
        }

        // Find the current user's attendance (marked with self: true)
        for attendee in attendees where attendee.self_ == true {
            return ResponseStatus(rawValue: attendee.responseStatus) ?? .needsAction
        }

        return .needsAction
    }
}

// MARK: - Response Types

/// Response from fetching events, containing events and optional sync token.
public struct EventsResponse: Sendable, Equatable {
    public let events: [CalendarEvent]
    public let nextSyncToken: String?

    public init(events: [CalendarEvent], nextSyncToken: String?) {
        self.events = events
        self.nextSyncToken = nextSyncToken
    }
}

/// Basic calendar information.
public struct CalendarInfo: Sendable, Equatable {
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
public enum CalendarAccessRole: String, Sendable, Equatable {
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

// MARK: - Google API Response Models

private struct CalendarListResponse: Codable {
    let items: [CalendarListItem]
}

private struct CalendarListItem: Codable {
    let id: String
    let summary: String
    let primary: Bool?
    let accessRole: String
}

private struct GoogleEventsResponse: Codable {
    let items: [GoogleEventItem]
    let nextSyncToken: String?
}

private struct GoogleEventItem: Codable {
    let id: String
    let summary: String?
    let description: String?
    let location: String?
    let start: GoogleEventTime?
    let end: GoogleEventTime?
    let hangoutLink: String?
    let conferenceData: GoogleConferenceData?
    let organizer: GoogleOrganizer?
    let attendees: [GoogleAttendee]?

    enum CodingKeys: String, CodingKey {
        case id, summary, description, location, start, end, hangoutLink, conferenceData, organizer, attendees
    }
}

private struct GoogleEventTime: Codable {
    let date: String?
    let dateTime: String?
    let timeZone: String?
}

private struct GoogleConferenceData: Codable {
    let entryPoints: [GoogleEntryPoint]?
}

private struct GoogleEntryPoint: Codable {
    let entryPointType: String
    let uri: String?
    let label: String?
}

private struct GoogleOrganizer: Codable {
    let email: String?
    let displayName: String?
    let self_: Bool?

    enum CodingKeys: String, CodingKey {
        case email, displayName
        case self_ = "self"
    }
}

private struct GoogleAttendee: Codable {
    let email: String
    let displayName: String?
    let responseStatus: String
    let self_: Bool?
    let organizer: Bool?

    enum CodingKeys: String, CodingKey {
        case email, displayName, responseStatus, organizer
        case self_ = "self"
    }
}

private struct GoogleErrorResponse: Codable {
    let error: GoogleError
}

private struct GoogleError: Codable {
    let code: Int
    let message: String
    let errors: [GoogleErrorDetail]
}

private struct GoogleErrorDetail: Codable {
    let domain: String
    let reason: String
    let message: String
}

// MARK: - JSON Decoder Extension

extension JSONDecoder {
    static let calendarDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
}
