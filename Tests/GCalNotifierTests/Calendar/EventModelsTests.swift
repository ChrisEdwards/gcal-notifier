import Foundation
import Testing

@testable import GCalNotifierCore

// MARK: - Test URLs

/// Static test URLs that are guaranteed to be valid.
/// Using an enum with static lets avoids force unwrapping in tests.
private enum TestURLs {
    static let googleMeet = URL(string: "https://meet.google.com/abc-defg-hij")
    static let googleMeetFirst = URL(string: "https://meet.google.com/first")
    static let googleMeetAbc = URL(string: "https://meet.google.com/abc")
    static let zoom = URL(string: "https://zoom.us/j/123456789")
    static let zoomShort = URL(string: "https://zoom.us/j/123")
    static let zoomSecond = URL(string: "https://zoom.us/second")
    static let zoomEncode = URL(string: "https://zoom.us/j/123456")
    static let zoomGov = URL(string: "https://example.zoomgov.com/j/123456789")
    static let teams = URL(string: "https://teams.microsoft.com/l/meetup-join/...")
    static let teamsLive = URL(string: "https://teams.live.com/meet/...")
    static let webex = URL(string: "https://example.webex.com/meet/user123")
    static let slackHuddle = URL(string: "https://app.slack.com/huddle/T12345/...")
    static let slackClient = URL(string: "https://app.slack.com/client/...")
    static let generic = URL(string: "https://example.com/meeting")
    static let custom = URL(string: "https://custom-meet.example.com/room")
}

// MARK: - Test Helpers

/// Creates a test CalendarEvent with default values that can be overridden.
private func makeEvent(
    id: String = "test-event-1",
    calendarId: String = "primary",
    title: String = "Test Meeting",
    startTime: Date = Date(),
    endTime: Date = Date().addingTimeInterval(3600),
    isAllDay: Bool = false,
    location: String? = nil,
    meetingLinks: [MeetingLink] = [],
    isOrganizer: Bool = false,
    attendeeCount: Int = 2,
    responseStatus: ResponseStatus = .accepted
) -> CalendarEvent {
    CalendarEvent(
        id: id,
        calendarId: calendarId,
        title: title,
        startTime: startTime,
        endTime: endTime,
        isAllDay: isAllDay,
        location: location,
        meetingLinks: meetingLinks,
        isOrganizer: isOrganizer,
        attendeeCount: attendeeCount,
        responseStatus: responseStatus
    )
}

// MARK: - ResponseStatus Tests

@Suite("ResponseStatus Tests")
struct ResponseStatusTests {
    @Test("Priority values are ordered correctly")
    func priorityOrdering() {
        #expect(ResponseStatus.declined.priority < ResponseStatus.needsAction.priority)
        #expect(ResponseStatus.needsAction.priority < ResponseStatus.tentative.priority)
        #expect(ResponseStatus.tentative.priority < ResponseStatus.accepted.priority)
    }

    @Test("Accepted has highest priority")
    func acceptedHighestPriority() {
        #expect(ResponseStatus.accepted.priority == 3)
    }

    @Test("Declined has lowest priority")
    func declinedLowestPriority() {
        #expect(ResponseStatus.declined.priority == 0)
    }

    @Test("All response statuses have distinct raw values")
    func distinctRawValues() {
        let allStatuses: [ResponseStatus] = [.accepted, .declined, .tentative, .needsAction]
        let rawValues = Set(allStatuses.map(\.rawValue))
        #expect(rawValues.count == 4)
    }
}

// MARK: - MeetingPlatform Detection Tests

@Suite("MeetingPlatform Detection Tests")
struct MeetingPlatformDetectionTests {
    @Test("Detects Google Meet URLs")
    func detectGoogleMeet() throws {
        let url = try #require(TestURLs.googleMeet)
        #expect(MeetingPlatform.detect(from: url) == .googleMeet)
    }

    @Test("Detects Zoom URLs")
    func detectZoom() throws {
        let url = try #require(TestURLs.zoom)
        #expect(MeetingPlatform.detect(from: url) == .zoom)
    }

    @Test("Detects ZoomGov URLs")
    func detectZoomGov() throws {
        let url = try #require(TestURLs.zoomGov)
        #expect(MeetingPlatform.detect(from: url) == .zoom)
    }

    @Test("Detects Microsoft Teams URLs")
    func detectTeams() throws {
        let url = try #require(TestURLs.teams)
        #expect(MeetingPlatform.detect(from: url) == .teams)
    }

    @Test("Detects Teams Live URLs")
    func detectTeamsLive() throws {
        let url = try #require(TestURLs.teamsLive)
        #expect(MeetingPlatform.detect(from: url) == .teams)
    }

    @Test("Detects Webex URLs")
    func detectWebex() throws {
        let url = try #require(TestURLs.webex)
        #expect(MeetingPlatform.detect(from: url) == .webex)
    }

    @Test("Detects Slack Huddle URLs")
    func detectSlackHuddle() throws {
        let url = try #require(TestURLs.slackHuddle)
        #expect(MeetingPlatform.detect(from: url) == .slackHuddle)
    }

    @Test("Returns unknown for non-meeting URLs")
    func detectUnknown() throws {
        let url = try #require(TestURLs.generic)
        #expect(MeetingPlatform.detect(from: url) == .unknown)
    }

    @Test("Handles Slack non-huddle URLs as unknown")
    func slackNonHuddle() throws {
        let url = try #require(TestURLs.slackClient)
        #expect(MeetingPlatform.detect(from: url) == .unknown)
    }
}

// MARK: - MeetingLink Tests

@Suite("MeetingLink Tests")
struct MeetingLinkTests {
    @Test("Init auto-detects platform from URL")
    func initAutoDetects() throws {
        let url = try #require(TestURLs.googleMeet)
        let link = MeetingLink(url: url)
        #expect(link.platform == .googleMeet)
    }

    @Test("Init accepts explicit platform override")
    func initExplicitPlatform() throws {
        let url = try #require(TestURLs.custom)
        let link = MeetingLink(url: url, platform: .zoom)
        #expect(link.platform == .zoom)
    }

    @Test("MeetingLink is equatable")
    func meetingLinkEquatable() throws {
        let url = try #require(TestURLs.zoomShort)
        let link1 = MeetingLink(url: url)
        let link2 = MeetingLink(url: url)
        #expect(link1 == link2)
    }
}

// MARK: - CalendarEvent Init Tests

@Suite("CalendarEvent Init Tests")
struct CalendarEventInitTests {
    @Test("Creates valid event with all fields")
    func initCreatesValidEvent() throws {
        let start = Date()
        let end = start.addingTimeInterval(3600)
        let meetingURL = try #require(TestURLs.googleMeetAbc)
        let meetingLink = MeetingLink(url: meetingURL)

        let event = CalendarEvent(
            id: "event-123",
            calendarId: "primary",
            title: "Team Standup",
            startTime: start,
            endTime: end,
            isAllDay: false,
            location: "Conference Room A",
            meetingLinks: [meetingLink],
            isOrganizer: true,
            attendeeCount: 5,
            responseStatus: .accepted
        )

        #expect(event.id == "event-123")
        #expect(event.calendarId == "primary")
        #expect(event.title == "Team Standup")
        #expect(event.startTime == start)
        #expect(event.endTime == end)
        #expect(event.isAllDay == false)
        #expect(event.location == "Conference Room A")
        #expect(event.meetingLinks.count == 1)
        #expect(event.isOrganizer == true)
        #expect(event.attendeeCount == 5)
        #expect(event.responseStatus == .accepted)
    }

    @Test("Event conforms to Identifiable")
    func eventIsIdentifiable() {
        let event = makeEvent(id: "unique-id")
        #expect(event.id == "unique-id")
    }
}

// MARK: - shouldAlert Tests

@Suite("shouldAlert Tests")
struct ShouldAlertTests {
    @Test("shouldAlert returns true with meeting link")
    func shouldAlertWithMeetingLink() throws {
        let meetingURL = try #require(TestURLs.googleMeetAbc)
        let meetingLink = MeetingLink(url: meetingURL)
        let event = makeEvent(meetingLinks: [meetingLink])
        #expect(event.shouldAlert == true)
    }

    @Test("shouldAlert returns false without meeting link")
    func shouldAlertWithoutMeetingLink() {
        let event = makeEvent(meetingLinks: [])
        #expect(event.shouldAlert == false)
    }

    @Test("shouldAlert returns false for all-day event even with meeting link")
    func shouldAlertAllDayEvent() throws {
        let meetingURL = try #require(TestURLs.googleMeetAbc)
        let meetingLink = MeetingLink(url: meetingURL)
        let event = makeEvent(isAllDay: true, meetingLinks: [meetingLink])
        #expect(event.shouldAlert == false)
    }

    @Test("shouldAlert returns false for all-day event without meeting link")
    func shouldAlertAllDayNoMeeting() {
        let event = makeEvent(isAllDay: true, meetingLinks: [])
        #expect(event.shouldAlert == false)
    }
}

// MARK: - primaryMeetingURL Tests

@Suite("primaryMeetingURL Tests")
struct PrimaryMeetingURLTests {
    @Test("primaryMeetingURL returns first link")
    func primaryMeetingURLReturnsFirst() throws {
        let url1 = try #require(TestURLs.googleMeetFirst)
        let url2 = try #require(TestURLs.zoomSecond)
        let link1 = MeetingLink(url: url1)
        let link2 = MeetingLink(url: url2)
        let event = makeEvent(meetingLinks: [link1, link2])

        #expect(event.primaryMeetingURL?.absoluteString == "https://meet.google.com/first")
    }

    @Test("primaryMeetingURL returns nil when no links")
    func primaryMeetingURLNilWhenEmpty() {
        let event = makeEvent(meetingLinks: [])
        #expect(event.primaryMeetingURL == nil)
    }
}

// MARK: - contextLine Tests

@Suite("contextLine Tests")
struct ContextLineTests {
    @Test("contextLine for organizer")
    func contextLineOrganizer() {
        let event = makeEvent(isOrganizer: true, attendeeCount: 8)
        #expect(event.contextLine == "👥 8 attendees · You're organizing")
    }

    @Test("contextLine for accepted attendee")
    func contextLineAccepted() {
        let event = makeEvent(isOrganizer: false, attendeeCount: 5, responseStatus: .accepted)
        #expect(event.contextLine == "👥 5 attendees · Accepted")
    }

    @Test("contextLine for tentative attendee")
    func contextLineTentative() {
        let event = makeEvent(isOrganizer: false, attendeeCount: 5, responseStatus: .tentative)
        #expect(event.contextLine == "👥 5 attendees · Tentative ⚠️")
    }

    @Test("contextLine for not responded")
    func contextLineNeedsAction() {
        let event = makeEvent(isOrganizer: false, attendeeCount: 3, responseStatus: .needsAction)
        #expect(event.contextLine == "👥 3 attendees · Not responded")
    }

    @Test("contextLine for declined")
    func contextLineDeclined() {
        let event = makeEvent(isOrganizer: false, attendeeCount: 4, responseStatus: .declined)
        #expect(event.contextLine == "👥 4 attendees · Declined")
    }

    @Test("contextLine for 1:1 meeting")
    func contextLineOneOnOne() {
        let event = makeEvent(isOrganizer: false, attendeeCount: 2, responseStatus: .accepted)
        #expect(event.contextLine == "👤 1:1 with colleague")
    }

    @Test("contextLine for 1:1 does not apply when organizer")
    func contextLineOneOnOneOrganizerException() {
        let event = makeEvent(isOrganizer: true, attendeeCount: 2)
        #expect(event.contextLine == "👥 2 attendees · You're organizing")
    }

    @Test("contextLine for interview")
    func contextLineInterview() {
        let event = makeEvent(title: "Interview with John Doe", isOrganizer: false, attendeeCount: 3)
        #expect(event.contextLine == "👤 Interview with candidate")
    }

    @Test("contextLine for interview case insensitive")
    func contextLineInterviewCaseInsensitive() {
        let event = makeEvent(title: "INTERVIEW - Engineering", isOrganizer: true, attendeeCount: 4)
        #expect(event.contextLine == "👤 Interview with candidate")
    }

    @Test("contextLine singular attendee")
    func contextLineSingularAttendee() {
        let event = makeEvent(isOrganizer: true, attendeeCount: 1)
        #expect(event.contextLine == "👥 1 attendee · You're organizing")
    }
}

// MARK: - Codable Tests

@Suite("CalendarEvent Codable Tests")
struct CalendarEventCodableTests {
    @Test("Encode and decode round-trips correctly")
    func encodeDecodeRoundTrip() throws {
        let meetingURL = try #require(TestURLs.googleMeet)
        let meetingLink = MeetingLink(url: meetingURL)
        let originalEvent = CalendarEvent(
            id: "event-encode-test",
            calendarId: "primary",
            title: "Round Trip Test",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_003_600),
            isAllDay: false,
            location: "Test Location",
            meetingLinks: [meetingLink],
            isOrganizer: true,
            attendeeCount: 3,
            responseStatus: .tentative
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(originalEvent)

        let decoder = JSONDecoder()
        let decodedEvent = try decoder.decode(CalendarEvent.self, from: data)

        #expect(decodedEvent.id == originalEvent.id)
        #expect(decodedEvent.calendarId == originalEvent.calendarId)
        #expect(decodedEvent.title == originalEvent.title)
        #expect(decodedEvent.startTime == originalEvent.startTime)
        #expect(decodedEvent.endTime == originalEvent.endTime)
        #expect(decodedEvent.isAllDay == originalEvent.isAllDay)
        #expect(decodedEvent.location == originalEvent.location)
        #expect(decodedEvent.meetingLinks == originalEvent.meetingLinks)
        #expect(decodedEvent.isOrganizer == originalEvent.isOrganizer)
        #expect(decodedEvent.attendeeCount == originalEvent.attendeeCount)
        #expect(decodedEvent.responseStatus == originalEvent.responseStatus)
    }

    @Test("MeetingLink encodes and decodes correctly")
    func meetingLinkEncodeDecode() throws {
        let meetingURL = try #require(TestURLs.zoomEncode)
        let originalLink = MeetingLink(url: meetingURL)

        let encoder = JSONEncoder()
        let data = try encoder.encode(originalLink)

        let decoder = JSONDecoder()
        let decodedLink = try decoder.decode(MeetingLink.self, from: data)

        #expect(decodedLink == originalLink)
    }

    @Test("ResponseStatus encodes and decodes correctly")
    func responseStatusEncodeDecode() throws {
        let allStatuses: [ResponseStatus] = [.accepted, .declined, .tentative, .needsAction]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in allStatuses {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(ResponseStatus.self, from: data)
            #expect(decoded == status)
        }
    }

    @Test("Event with nil location encodes correctly")
    func nilLocationEncodes() throws {
        let event = makeEvent(location: nil)

        let encoder = JSONEncoder()
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        let decodedEvent = try decoder.decode(CalendarEvent.self, from: data)

        #expect(decodedEvent.location == nil)
    }

    @Test("Event with empty meeting links encodes correctly")
    func emptyMeetingLinksEncode() throws {
        let event = makeEvent(meetingLinks: [])

        let encoder = JSONEncoder()
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        let decodedEvent = try decoder.decode(CalendarEvent.self, from: data)

        #expect(decodedEvent.meetingLinks.isEmpty)
    }
}

// MARK: - Equatable Tests

@Suite("CalendarEvent Equatable Tests")
struct CalendarEventEquatableTests {
    @Test("Same events are equal")
    func sameEventsEqual() {
        let fixedTime = Date(timeIntervalSince1970: 1_700_000_000)
        let fixedEndTime = fixedTime.addingTimeInterval(3600)
        let event1 = makeEvent(id: "same-id", title: "Same Title", startTime: fixedTime, endTime: fixedEndTime)
        let event2 = makeEvent(id: "same-id", title: "Same Title", startTime: fixedTime, endTime: fixedEndTime)
        #expect(event1 == event2)
    }

    @Test("Different IDs make events not equal")
    func differentIdsNotEqual() {
        let fixedTime = Date(timeIntervalSince1970: 1_700_000_000)
        let fixedEndTime = fixedTime.addingTimeInterval(3600)
        let event1 = makeEvent(id: "id-1", startTime: fixedTime, endTime: fixedEndTime)
        let event2 = makeEvent(id: "id-2", startTime: fixedTime, endTime: fixedEndTime)
        #expect(event1 != event2)
    }
}
