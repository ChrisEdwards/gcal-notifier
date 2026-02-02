import Foundation
import Testing
@testable import GCalNotifierCore

// MARK: - Test Helpers

/// Creates an isolated UserDefaults suite for test isolation.
private func makeTestDefaults() -> UserDefaults {
    let suiteName = "EventFilterTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        return .standard
    }
    return defaults
}

/// Static test URLs for meeting links.
private enum TestURLs {
    static let googleMeet = URL(string: "https://meet.google.com/abc-defg-hij")
}

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

/// Creates an EventFilter with a test SettingsStore.
private func makeFilter(
    enabledCalendars: [String] = [],
    blockedKeywords: [String] = [],
    forceAlertKeywords: [String] = []
) -> EventFilter {
    let defaults = makeTestDefaults()
    let settings = SettingsStore(defaults: defaults)
    settings.enabledCalendars = enabledCalendars
    settings.blockedKeywords = blockedKeywords
    settings.forceAlertKeywords = forceAlertKeywords
    return EventFilter(settings: settings)
}

// MARK: - Meeting Link Filter Tests

@Suite("EventFilter Meeting Link Tests")
struct EventFilterMeetingLinkTests {
    @Test("Event with meeting link passes filter")
    func eventWithMeetingLink_passes() throws {
        let meetingURL = try #require(TestURLs.googleMeet)
        let meetingLink = MeetingLink(url: meetingURL)
        let event = makeEvent(meetingLinks: [meetingLink])
        let filter = makeFilter()

        #expect(filter.shouldAlert(for: event) == true)
    }

    @Test("Event without meeting link fails filter")
    func eventWithoutMeetingLink_fails() {
        let event = makeEvent(meetingLinks: [])
        let filter = makeFilter()

        #expect(filter.shouldAlert(for: event) == false)
    }
}

// MARK: - Calendar Enable/Disable Tests

@Suite("EventFilter Calendar Tests")
struct EventFilterCalendarTests {
    @Test("Event from enabled calendar passes filter")
    func enabledCalendar_passes() throws {
        let meetingURL = try #require(TestURLs.googleMeet)
        let meetingLink = MeetingLink(url: meetingURL)
        let event = makeEvent(calendarId: "work@example.com", meetingLinks: [meetingLink])
        let filter = makeFilter(enabledCalendars: ["work@example.com", "personal@example.com"])

        #expect(filter.shouldAlert(for: event) == true)
    }

    @Test("Event from disabled calendar fails filter")
    func disabledCalendar_fails() throws {
        let meetingURL = try #require(TestURLs.googleMeet)
        let meetingLink = MeetingLink(url: meetingURL)
        let event = makeEvent(calendarId: "other@example.com", meetingLinks: [meetingLink])
        let filter = makeFilter(enabledCalendars: ["work@example.com", "personal@example.com"])

        #expect(filter.shouldAlert(for: event) == false)
    }

    @Test("Empty enabled calendars means all calendars pass")
    func emptyEnabledCalendars_allPass() throws {
        let meetingURL = try #require(TestURLs.googleMeet)
        let meetingLink = MeetingLink(url: meetingURL)
        let event = makeEvent(calendarId: "any-calendar", meetingLinks: [meetingLink])
        let filter = makeFilter(enabledCalendars: [])

        #expect(filter.shouldAlert(for: event) == true)
    }
}

// MARK: - Force Alert Keyword Tests

@Suite("EventFilter Force Alert Keyword Tests")
struct EventFilterForceAlertKeywordTests {
    @Test("Force alert keyword in title passes without meeting link")
    func forceAlertKeywordInTitle_passesWithoutMeetingLink() {
        let event = makeEvent(title: "Interview with John", meetingLinks: [])
        let filter = makeFilter(forceAlertKeywords: ["Interview"])

        #expect(filter.shouldAlert(for: event) == true)
    }

    @Test("Force alert keyword in location passes without meeting link")
    func forceAlertKeywordInLocation_passesWithoutMeetingLink() {
        let event = makeEvent(
            title: "Team Meeting",
            location: "IMPORTANT Room 101",
            meetingLinks: []
        )
        let filter = makeFilter(forceAlertKeywords: ["IMPORTANT"])

        #expect(filter.shouldAlert(for: event) == true)
    }

    @Test("Force alert keyword matching is case insensitive")
    func forceAlertKeyword_caseInsensitive() {
        let event = makeEvent(title: "interview with candidate", meetingLinks: [])
        let filter = makeFilter(forceAlertKeywords: ["Interview"])

        #expect(filter.shouldAlert(for: event) == true)
    }

    @Test("Force alert keyword matching is substring match")
    func forceAlertKeyword_substringMatch() {
        let event = makeEvent(title: "Technical Interview Session", meetingLinks: [])
        let filter = makeFilter(forceAlertKeywords: ["Interview"])

        #expect(filter.shouldAlert(for: event) == true)
    }
}

// MARK: - Blocked Keyword Tests

@Suite("EventFilter Blocked Keyword Tests")
struct EventFilterBlockedKeywordTests {
    @Test("Blocked keyword in title fails filter")
    func blockedKeywordInTitle_fails() throws {
        let meetingURL = try #require(TestURLs.googleMeet)
        let meetingLink = MeetingLink(url: meetingURL)
        let event = makeEvent(title: "Optional team lunch", meetingLinks: [meetingLink])
        let filter = makeFilter(blockedKeywords: ["lunch", "optional"])

        #expect(filter.shouldAlert(for: event) == false)
    }

    @Test("Blocked keyword in location fails filter")
    func blockedKeywordInLocation_fails() throws {
        let meetingURL = try #require(TestURLs.googleMeet)
        let meetingLink = MeetingLink(url: meetingURL)
        let event = makeEvent(
            title: "Team Meeting",
            location: "lunch room",
            meetingLinks: [meetingLink]
        )
        let filter = makeFilter(blockedKeywords: ["lunch"])

        #expect(filter.shouldAlert(for: event) == false)
    }

    @Test("Blocked keyword overrides force alert keyword")
    func blockedKeyword_overridesForceAlert() {
        let event = makeEvent(
            title: "IMPORTANT optional meeting",
            meetingLinks: []
        )
        let filter = makeFilter(
            blockedKeywords: ["optional"],
            forceAlertKeywords: ["IMPORTANT"]
        )

        #expect(filter.shouldAlert(for: event) == false)
    }

    @Test("Blocked keyword matching is case insensitive")
    func blockedKeyword_caseInsensitive() throws {
        let meetingURL = try #require(TestURLs.googleMeet)
        let meetingLink = MeetingLink(url: meetingURL)
        let event = makeEvent(title: "LUNCH break meeting", meetingLinks: [meetingLink])
        let filter = makeFilter(blockedKeywords: ["lunch"])

        #expect(filter.shouldAlert(for: event) == false)
    }
}

// MARK: - All-Day Event Tests

@Suite("EventFilter All-Day Event Tests")
struct EventFilterAllDayEventTests {
    @Test("All-day event always fails filter")
    func allDayEvent_alwaysFails() throws {
        let meetingURL = try #require(TestURLs.googleMeet)
        let meetingLink = MeetingLink(url: meetingURL)
        let event = makeEvent(
            title: "All-Day Conference",
            isAllDay: true,
            meetingLinks: [meetingLink]
        )
        let filter = makeFilter()

        #expect(filter.shouldAlert(for: event) == false)
    }

    @Test("All-day event with force-alert keyword still fails")
    func allDayEvent_forceAlertKeywordStillFails() {
        let event = makeEvent(
            title: "IMPORTANT All-Day Event",
            isAllDay: true,
            meetingLinks: []
        )
        let filter = makeFilter(forceAlertKeywords: ["IMPORTANT"])

        #expect(filter.shouldAlert(for: event) == false)
    }
}

// MARK: - Combined Filter Tests

@Suite("EventFilter Combined Filter Tests")
struct EventFilterCombinedTests {
    @Test("Event must pass all checks")
    func eventMustPassAllChecks() throws {
        let meetingURL = try #require(TestURLs.googleMeet)
        let meetingLink = MeetingLink(url: meetingURL)
        let event = makeEvent(
            calendarId: "work@example.com",
            title: "Team Standup",
            meetingLinks: [meetingLink]
        )
        let filter = makeFilter(
            enabledCalendars: ["work@example.com"],
            blockedKeywords: [],
            forceAlertKeywords: []
        )

        #expect(filter.shouldAlert(for: event) == true)
    }

    @Test("Fails if any check fails")
    func failsIfAnyCheckFails() throws {
        let meetingURL = try #require(TestURLs.googleMeet)
        let meetingLink = MeetingLink(url: meetingURL)

        // Has meeting link but wrong calendar
        let event = makeEvent(
            calendarId: "personal@example.com",
            title: "Team Standup",
            meetingLinks: [meetingLink]
        )
        let filter = makeFilter(enabledCalendars: ["work@example.com"])

        #expect(filter.shouldAlert(for: event) == false)
    }

    @Test("Event with nil location and no meeting link fails")
    func nilLocationNoMeetingLink_fails() {
        let event = makeEvent(
            title: "Quick Chat",
            location: nil,
            meetingLinks: []
        )
        let filter = makeFilter()

        #expect(filter.shouldAlert(for: event) == false)
    }

    @Test("Event with nil location but force-alert keyword passes")
    func nilLocationWithForceKeyword_passes() {
        let event = makeEvent(
            title: "Interview Call",
            location: nil,
            meetingLinks: []
        )
        let filter = makeFilter(forceAlertKeywords: ["Interview"])

        #expect(filter.shouldAlert(for: event) == true)
    }
}
