import Foundation
import Testing
@testable import GCalNotifierCore

// MARK: - Test Helpers

private actor MockTokenProvider: AccessTokenProvider {
    var accessToken: String = "test-access-token"
    var errorToThrow: Error?

    func getAccessToken() async throws -> String {
        if let error = errorToThrow { throw error }
        return self.accessToken
    }

    func setAccessToken(_ token: String) {
        self.accessToken = token
    }

    func setError(_ error: Error?) {
        self.errorToThrow = error
    }
}

private struct CalendarClientTestContext {
    let client: GoogleCalendarClient
    let httpClient: MockHTTPClient
    let tokenProvider: MockTokenProvider
}

private func makeCalendarClientTestContext() -> CalendarClientTestContext {
    let httpClient = MockHTTPClient()
    let tokenProvider = MockTokenProvider()
    let client = GoogleCalendarClient(httpClient: httpClient, tokenProvider: tokenProvider)
    return CalendarClientTestContext(client: client, httpClient: httpClient, tokenProvider: tokenProvider)
}

// MARK: - Test JSON Helpers

private func makeEventsResponseJSON(events: [String] = [], nextSyncToken: String? = nil) -> Data {
    let itemsJSON = events.joined(separator: ",")
    var json = "{\"items\": [\(itemsJSON)]"
    if let token = nextSyncToken { json += ",\"nextSyncToken\": \"\(token)\"" }
    return Data((json + "}").utf8)
}

private func makeEventJSON(
    id: String = "event-123",
    summary: String = "Team Meeting",
    start: String = "2026-01-23T10:00:00Z",
    end: String = "2026-01-23T11:00:00Z",
    extras: [String] = []
) -> String {
    var parts = [
        "\"id\": \"\(id)\"",
        "\"summary\": \"\(summary)\"",
        "\"start\": {\"dateTime\": \"\(start)\"}",
        "\"end\": {\"dateTime\": \"\(end)\"}",
    ]
    parts.append(contentsOf: extras)
    return "{\(parts.joined(separator: ","))}"
}

private func makeCalendarListResponseJSON(calendars: [String]) -> Data {
    Data("{\"items\": [\(calendars.joined(separator: ","))]}".utf8)
}

private func makeCalendarJSON(
    id: String,
    summary: String,
    primary: Bool? = nil,
    accessRole: String = "owner"
) -> String {
    var json = "{\"id\": \"\(id)\",\"summary\": \"\(summary)\",\"accessRole\": \"\(accessRole)\""
    if let isPrimary = primary { json += ",\"primary\": \(isPrimary)" }
    return json + "}"
}

private func makeErrorJSON(code: Int, message: String, reason: String = "unknown") -> Data {
    Data("""
    {"error":{"code":\(code),"message":"\(message)","errors":[{"domain":"global","reason":"\(reason)","message":"\(
        message
    )"}]}}
    """.utf8)
}

// MARK: - Tests

@Suite("GoogleCalendarClient Tests", .serialized)
struct GoogleCalendarClientTests {
    @Test("fetchEvents success returns events")
    func fetchEventsSuccessReturnsEvents() async throws {
        let ctx = makeCalendarClientTestContext()
        let eventJSON = makeEventJSON(id: "event-123", summary: "Team Standup")
        await ctx.httpClient.queueResponse(
            data: makeEventsResponseJSON(events: [eventJSON], nextSyncToken: "sync-token-1"),
            statusCode: 200
        )
        let response = try await ctx.client.fetchEvents(calendarId: "primary")
        #expect(response.events.count == 1)
        #expect(response.events[0].id == "event-123")
        #expect(response.events[0].title == "Team Standup")
        #expect(response.nextSyncToken == "sync-token-1")
        #expect(response.deletedEventIds.isEmpty)
    }

    @Test("fetchEvents with syncToken sends token in request")
    func fetchEventsWithSyncTokenSendsToken() async throws {
        let ctx = makeCalendarClientTestContext()
        await ctx.httpClient.queueResponse(data: makeEventsResponseJSON(events: []), statusCode: 200)
        _ = try await ctx.client.fetchEvents(calendarId: "primary", syncToken: "my-sync-token")
        let requests = await ctx.httpClient.requestsReceived
        #expect(requests.count == 1)
        let requestURL = requests[0].url?.absoluteString ?? ""
        #expect(requestURL.contains("syncToken=my-sync-token"))
        #expect(requestURL.contains("singleEvents=true"))
        #expect(requestURL.contains("showDeleted=true"))
        #expect(!requestURL.contains("orderBy=startTime"))
        #expect(!requestURL.contains("timeMin="))
        #expect(!requestURL.contains("timeMax="))
    }

    @Test("fetchCalendarList success returns calendars")
    func fetchCalendarListSuccessReturnsCalendars() async throws {
        let ctx = makeCalendarClientTestContext()
        let calendar1 = makeCalendarJSON(id: "primary", summary: "Primary Calendar", primary: true)
        let calendar2 = makeCalendarJSON(id: "work", summary: "Work Calendar", accessRole: "reader")
        await ctx.httpClient.queueResponse(
            data: makeCalendarListResponseJSON(calendars: [calendar1, calendar2]),
            statusCode: 200
        )
        let calendars = try await ctx.client.fetchCalendarList()
        #expect(calendars.count == 2)
        #expect(calendars[0].id == "primary")
        #expect(calendars[0].isPrimary == true)
        #expect(calendars[0].accessRole == .owner)
        #expect(calendars[1].accessRole == .reader)
    }

    @Test("fetchEvents 401 throws authenticationRequired")
    func fetchEvents401ThrowsAuthenticationRequired() async throws {
        let ctx = makeCalendarClientTestContext()
        await ctx.httpClient.queueResponse(
            data: makeErrorJSON(code: 401, message: "Invalid credentials"),
            statusCode: 401
        )
        await #expect(throws: CalendarError.authenticationRequired) {
            _ = try await ctx.client.fetchEvents(calendarId: "primary")
        }
    }

    @Test("fetchEvents 403 rateLimitExceeded throws rateLimited")
    func fetchEvents403RateLimitedThrowsRateLimited() async throws {
        let ctx = makeCalendarClientTestContext()
        await ctx.httpClient.queueResponse(
            data: makeErrorJSON(code: 403, message: "Rate limit exceeded", reason: "rateLimitExceeded"),
            statusCode: 403
        )
        do {
            _ = try await ctx.client.fetchEvents(calendarId: "primary")
            Issue.record("Expected rateLimited error")
        } catch let error as CalendarError {
            guard case .rateLimited = error else { Issue.record("Expected rateLimited, got \(error)"); return }
        }
    }

    @Test("fetchEvents 403 non-rate-limit throws invalidRequest")
    func fetchEvents403NonRateLimitedThrowsInvalidRequest() async throws {
        let ctx = makeCalendarClientTestContext()
        await ctx.httpClient.queueResponse(
            data: makeErrorJSON(code: 403, message: "Forbidden", reason: "insufficientPermissions"),
            statusCode: 403
        )
        do {
            _ = try await ctx.client.fetchEvents(calendarId: "primary")
            Issue.record("Expected invalidRequest error")
        } catch let error as CalendarError {
            guard case .invalidRequest = error else { Issue.record("Expected invalidRequest, got \(error)"); return }
        }
    }

    @Test("fetchEvents 410 throws syncTokenInvalid")
    func fetchEvents410ThrowsSyncTokenInvalid() async throws {
        let ctx = makeCalendarClientTestContext()
        await ctx.httpClient.queueResponse(data: makeErrorJSON(code: 410, message: "Token invalid"), statusCode: 410)
        await #expect(throws: CalendarError.syncTokenInvalid) {
            _ = try await ctx.client.fetchEvents(calendarId: "primary", syncToken: "old-token")
        }
    }

    @Test("fetchEvents 404 throws calendarNotFound")
    func fetchEvents404ThrowsCalendarNotFound() async throws {
        let ctx = makeCalendarClientTestContext()
        await ctx.httpClient.queueResponse(data: makeErrorJSON(code: 404, message: "Not found"), statusCode: 404)
        do {
            _ = try await ctx.client.fetchEvents(calendarId: "nonexistent-calendar")
            Issue.record("Expected calendarNotFound error")
        } catch let error as CalendarError {
            guard case let .calendarNotFound(calId) = error else { Issue.record("Wrong error"); return }
            #expect(calId == "nonexistent-calendar")
        }
    }

    @Test("fetchEvents uses access token in request")
    func fetchEventsUsesAccessToken() async throws {
        let ctx = makeCalendarClientTestContext()
        await ctx.tokenProvider.setAccessToken("my-special-token")
        await ctx.httpClient.queueResponse(data: makeEventsResponseJSON(events: []), statusCode: 200)
        _ = try await ctx.client.fetchEvents(calendarId: "primary")
        let requests = await ctx.httpClient.requestsReceived
        #expect(requests.count == 1)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer my-special-token")
    }

    @Test("fetchEvents when token provider fails throws authenticationRequired")
    func fetchEventsTokenProviderFailsThrowsAuthenticationRequired() async throws {
        let ctx = makeCalendarClientTestContext()
        await ctx.tokenProvider.setError(OAuthError.notAuthenticated)
        await #expect(throws: CalendarError.authenticationRequired) {
            _ = try await ctx.client.fetchEvents(calendarId: "primary")
        }
    }

    @Test("fetchEvents 500 throws serverError")
    func fetchEvents500ThrowsServerError() async throws {
        let ctx = makeCalendarClientTestContext()
        await ctx.httpClient.queueResponse(data: makeErrorJSON(code: 500, message: "Server error"), statusCode: 500)
        do {
            _ = try await ctx.client.fetchEvents(calendarId: "primary")
            Issue.record("Expected serverError")
        } catch let error as CalendarError {
            guard case let .serverError(statusCode, _) = error else { Issue.record("Wrong error"); return }
            #expect(statusCode == 500)
        }
    }

    @Test("fetchEvents extracts hangout link")
    func fetchEventsExtractsHangoutLink() async throws {
        let ctx = makeCalendarClientTestContext()
        let eventJSON = makeEventJSON(
            id: "event-meet",
            summary: "Quick Sync",
            extras: ["\"hangoutLink\": \"https://meet.google.com/abc-defg-hij\""]
        )
        await ctx.httpClient.queueResponse(data: makeEventsResponseJSON(events: [eventJSON]), statusCode: 200)
        let response = try await ctx.client.fetchEvents(calendarId: "primary")
        #expect(response.events.count == 1)
        #expect(response.events[0].meetingLinks.count == 1)
        #expect(response.events[0].meetingLinks[0].platform == .googleMeet)
    }

    @Test("fetchEvents extracts conference data")
    func fetchEventsExtractsConferenceData() async throws {
        let ctx = makeCalendarClientTestContext()
        let entryPoint = "{\"entryPointType\":\"video\",\"uri\":\"https://zoom.us/j/123\"}"
        let conf = "\"conferenceData\":{\"entryPoints\":[\(entryPoint)]}"
        let eventJSON = makeEventJSON(id: "event-zoom", summary: "Zoom Call", extras: [conf])
        await ctx.httpClient.queueResponse(data: makeEventsResponseJSON(events: [eventJSON]), statusCode: 200)
        let response = try await ctx.client.fetchEvents(calendarId: "primary")
        #expect(response.events[0].meetingLinks[0].platform == .zoom)
    }

    @Test("fetchEvents with date range sends timeMin and timeMax")
    func fetchEventsWithDateRangeSendsTimeMinMax() async throws {
        let ctx = makeCalendarClientTestContext()
        await ctx.httpClient.queueResponse(data: makeEventsResponseJSON(events: []), statusCode: 200)
        let fromDate = Date()
        let toDate = fromDate.addingTimeInterval(86400)
        _ = try await ctx.client.fetchEvents(calendarId: "primary", from: fromDate, to: toDate)
        let requests = await ctx.httpClient.requestsReceived
        let requestURL = requests[0].url?.absoluteString ?? ""
        #expect(requestURL.contains("timeMin="))
        #expect(requestURL.contains("timeMax="))
    }

    @Test("fetchEvents parses response status from attendees")
    func fetchEventsParsesResponseStatus() async throws {
        let ctx = makeCalendarClientTestContext()
        let attendees = "\"attendees\":[{\"email\":\"a@b.com\",\"responseStatus\":\"accepted\"}," +
            "{\"email\":\"me@b.com\",\"responseStatus\":\"tentative\",\"self\":true}]"
        let eventJSON = makeEventJSON(id: "event-att", summary: "Meeting", extras: [attendees])
        await ctx.httpClient.queueResponse(data: makeEventsResponseJSON(events: [eventJSON]), statusCode: 200)
        let response = try await ctx.client.fetchEvents(calendarId: "primary")
        #expect(response.events[0].responseStatus == .tentative)
        #expect(response.events[0].attendeeCount == 2)
    }

    @Test("fetchEvents parses organizer self flag")
    func fetchEventsParsesOrganizerSelf() async throws {
        let ctx = makeCalendarClientTestContext()
        let organizer = "\"organizer\":{\"email\":\"me@example.com\",\"self\":true}"
        let eventJSON = makeEventJSON(id: "event-org", summary: "My Meeting", extras: [organizer])
        await ctx.httpClient.queueResponse(data: makeEventsResponseJSON(events: [eventJSON]), statusCode: 200)
        let response = try await ctx.client.fetchEvents(calendarId: "primary")
        #expect(response.events[0].isOrganizer == true)
    }

    @Test("fetchEvents captures cancelled events as deletions")
    func fetchEventsCapturesCancelledEventsAsDeletions() async throws {
        let ctx = makeCalendarClientTestContext()
        let cancelledEventJSON = "{\"id\":\"event-cancelled\",\"status\":\"cancelled\"}"
        let activeEventJSON = makeEventJSON(id: "event-active", summary: "Active Meeting")
        await ctx.httpClient.queueResponse(
            data: makeEventsResponseJSON(events: [cancelledEventJSON, activeEventJSON]),
            statusCode: 200
        )
        let response = try await ctx.client.fetchEvents(calendarId: "primary")
        #expect(response.events.count == 1)
        #expect(response.events[0].id == "event-active")
        #expect(response.deletedEventIds == ["event-cancelled"])
    }
}
