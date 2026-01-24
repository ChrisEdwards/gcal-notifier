import Foundation
import Testing

@testable import GCalNotifierCore

// MARK: - Test URLs

/// Static test URLs for back-to-back tests.
private enum TestURLs {
    static let googleMeet = URL(string: "https://meet.google.com/abc-defg-hij")
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

// MARK: - isBackToBack Tests

@Suite("isBackToBack Tests")
struct IsBackToBackTests {
    @Test("Returns true when next meeting starts immediately after current ends")
    func backToBackNoGap() {
        let now = Date()
        let event1 = makeEvent(
            id: "event-1",
            startTime: now,
            endTime: now.addingTimeInterval(3600) // Ends in 1 hour
        )
        let event2 = makeEvent(
            id: "event-2",
            startTime: now.addingTimeInterval(3600), // Starts exactly when event1 ends
            endTime: now.addingTimeInterval(7200)
        )
        #expect(event1.isBackToBack(with: event2) == true)
    }

    @Test("Returns true when next meeting starts within 5 minutes of current ending")
    func backToBackWithinThreshold() {
        let now = Date()
        let event1 = makeEvent(
            id: "event-1",
            startTime: now,
            endTime: now.addingTimeInterval(3600) // Ends in 1 hour
        )
        let event2 = makeEvent(
            id: "event-2",
            startTime: now.addingTimeInterval(3600 + 300), // Starts 5 minutes after event1 ends
            endTime: now.addingTimeInterval(7200)
        )
        #expect(event1.isBackToBack(with: event2) == true)
    }

    @Test("Returns false when next meeting starts more than 5 minutes after current ends")
    func notBackToBackBeyondThreshold() {
        let now = Date()
        let event1 = makeEvent(
            id: "event-1",
            startTime: now,
            endTime: now.addingTimeInterval(3600) // Ends in 1 hour
        )
        let event2 = makeEvent(
            id: "event-2",
            startTime: now.addingTimeInterval(3600 + 301), // Starts 5m01s after - just over threshold
            endTime: now.addingTimeInterval(7200)
        )
        #expect(event1.isBackToBack(with: event2) == false)
    }

    @Test("Returns false when next meeting starts before current ends (overlap)")
    func notBackToBackOverlapping() {
        let now = Date()
        let event1 = makeEvent(
            id: "event-1",
            startTime: now,
            endTime: now.addingTimeInterval(3600) // Ends in 1 hour
        )
        let event2 = makeEvent(
            id: "event-2",
            startTime: now.addingTimeInterval(1800), // Starts 30 min into event1
            endTime: now.addingTimeInterval(5400)
        )
        #expect(event1.isBackToBack(with: event2) == false)
    }

    @Test("Threshold constant is 5 minutes")
    func thresholdValue() {
        #expect(CalendarEvent.backToBackThreshold == 5 * 60)
    }
}

// MARK: - isInProgress Tests

@Suite("isInProgress Tests")
struct IsInProgressTests {
    @Test("Returns true when current time is between start and end")
    func inProgressDuringMeeting() {
        let now = Date()
        let event = makeEvent(
            startTime: now.addingTimeInterval(-1800), // Started 30 min ago
            endTime: now.addingTimeInterval(1800) // Ends in 30 min
        )
        #expect(event.isInProgress(at: now) == true)
    }

    @Test("Returns true at exact start time")
    func inProgressAtStart() {
        let now = Date()
        let event = makeEvent(
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )
        #expect(event.isInProgress(at: now) == true)
    }

    @Test("Returns false at exact end time")
    func notInProgressAtEnd() {
        let now = Date()
        let event = makeEvent(
            startTime: now.addingTimeInterval(-3600),
            endTime: now
        )
        #expect(event.isInProgress(at: now) == false)
    }

    @Test("Returns false before meeting starts")
    func notInProgressBeforeStart() {
        let now = Date()
        let event = makeEvent(
            startTime: now.addingTimeInterval(3600), // Starts in 1 hour
            endTime: now.addingTimeInterval(7200)
        )
        #expect(event.isInProgress(at: now) == false)
    }

    @Test("Returns false after meeting ends")
    func notInProgressAfterEnd() {
        let now = Date()
        let event = makeEvent(
            startTime: now.addingTimeInterval(-7200), // Started 2 hours ago
            endTime: now.addingTimeInterval(-3600) // Ended 1 hour ago
        )
        #expect(event.isInProgress(at: now) == false)
    }
}

// MARK: - hasVideoLink Tests

@Suite("hasVideoLink Tests")
struct HasVideoLinkTests {
    @Test("Returns true when meeting has video links")
    func hasVideoLinkTrue() throws {
        let url = try #require(TestURLs.googleMeet)
        let link = MeetingLink(url: url)
        let event = makeEvent(meetingLinks: [link])
        #expect(event.hasVideoLink == true)
    }

    @Test("Returns false when meeting has no video links")
    func hasVideoLinkFalse() {
        let event = makeEvent(meetingLinks: [])
        #expect(event.hasVideoLink == false)
    }
}

// MARK: - BackToBackState Tests

@Suite("BackToBackState Tests")
struct BackToBackStateTests {
    @Test("isBackToBack returns true when both current and next are set")
    func isBackToBackTrue() throws {
        let now = Date()
        let url = try #require(TestURLs.googleMeet)
        let link = MeetingLink(url: url)

        let current = makeEvent(
            id: "current",
            startTime: now.addingTimeInterval(-1800),
            endTime: now.addingTimeInterval(600),
            meetingLinks: [link]
        )
        let next = makeEvent(
            id: "next",
            startTime: now.addingTimeInterval(600),
            endTime: now.addingTimeInterval(4200),
            meetingLinks: [link]
        )

        let state = BackToBackState(currentMeeting: current, nextBackToBackMeeting: next)
        #expect(state.isBackToBack == true)
    }

    @Test("isBackToBack returns false when current is nil")
    func isBackToBackFalseNoCurrentMeeting() throws {
        let now = Date()
        let url = try #require(TestURLs.googleMeet)
        let link = MeetingLink(url: url)

        let next = makeEvent(
            id: "next",
            startTime: now.addingTimeInterval(600),
            endTime: now.addingTimeInterval(4200),
            meetingLinks: [link]
        )

        let state = BackToBackState(currentMeeting: nil, nextBackToBackMeeting: next)
        #expect(state.isBackToBack == false)
    }

    @Test("isBackToBack returns false when next is nil")
    func isBackToBackFalseNoNextMeeting() throws {
        let now = Date()
        let url = try #require(TestURLs.googleMeet)
        let link = MeetingLink(url: url)

        let current = makeEvent(
            id: "current",
            startTime: now.addingTimeInterval(-1800),
            endTime: now.addingTimeInterval(600),
            meetingLinks: [link]
        )

        let state = BackToBackState(currentMeeting: current, nextBackToBackMeeting: nil)
        #expect(state.isBackToBack == false)
    }

    @Test("none state has nil meetings")
    func noneStateHasNilMeetings() {
        let state = BackToBackState.none
        #expect(state.currentMeeting == nil)
        #expect(state.nextBackToBackMeeting == nil)
        #expect(state.isBackToBack == false)
    }
}

// MARK: - BackToBackState Detection Tests

@Suite("BackToBackState Detection Tests")
struct BackToBackStateDetectionTests {
    @Test("Detects back-to-back situation when in meeting with upcoming back-to-back")
    func detectsBackToBack() throws {
        let now = Date()
        let url = try #require(TestURLs.googleMeet)
        let link = MeetingLink(url: url)

        let current = makeEvent(
            id: "current",
            startTime: now.addingTimeInterval(-1800), // Started 30 min ago
            endTime: now.addingTimeInterval(600), // Ends in 10 min
            meetingLinks: [link]
        )
        let next = makeEvent(
            id: "next",
            startTime: now.addingTimeInterval(600), // Starts when current ends
            endTime: now.addingTimeInterval(4200),
            meetingLinks: [link]
        )
        let unrelated = makeEvent(
            id: "unrelated",
            startTime: now.addingTimeInterval(7200), // Starts in 2 hours
            endTime: now.addingTimeInterval(10800),
            meetingLinks: [link]
        )

        let state = BackToBackState.detect(from: [current, next, unrelated], now: now)

        #expect(state.isBackToBack == true)
        #expect(state.currentMeeting?.id == "current")
        #expect(state.nextBackToBackMeeting?.id == "next")
    }

    @Test("Returns .none when not in any meeting")
    func detectsNoBackToBackWhenNotInMeeting() throws {
        let now = Date()
        let url = try #require(TestURLs.googleMeet)
        let link = MeetingLink(url: url)

        let future = makeEvent(
            id: "future",
            startTime: now.addingTimeInterval(3600),
            endTime: now.addingTimeInterval(7200),
            meetingLinks: [link]
        )

        let state = BackToBackState.detect(from: [future], now: now)

        #expect(state.isBackToBack == false)
        #expect(state.currentMeeting == nil)
    }

    @Test("Returns state with nil next when in meeting but no back-to-back")
    func detectsNoNextBackToBack() throws {
        let now = Date()
        let url = try #require(TestURLs.googleMeet)
        let link = MeetingLink(url: url)

        let current = makeEvent(
            id: "current",
            startTime: now.addingTimeInterval(-1800),
            endTime: now.addingTimeInterval(600),
            meetingLinks: [link]
        )
        let farFuture = makeEvent(
            id: "far-future",
            startTime: now.addingTimeInterval(7200), // Starts 2 hours from now (not back-to-back)
            endTime: now.addingTimeInterval(10800),
            meetingLinks: [link]
        )

        let state = BackToBackState.detect(from: [current, farFuture], now: now)

        #expect(state.isBackToBack == false)
        #expect(state.currentMeeting?.id == "current")
        #expect(state.nextBackToBackMeeting == nil)
    }

    @Test("Ignores events without video links for current meeting detection")
    func ignoresEventsWithoutVideoLinks() throws {
        let now = Date()
        let url = try #require(TestURLs.googleMeet)
        let link = MeetingLink(url: url)

        let noVideoMeeting = makeEvent(
            id: "no-video",
            startTime: now.addingTimeInterval(-1800),
            endTime: now.addingTimeInterval(600),
            meetingLinks: [] // No video link
        )
        let videoMeeting = makeEvent(
            id: "video",
            startTime: now.addingTimeInterval(600),
            endTime: now.addingTimeInterval(4200),
            meetingLinks: [link]
        )

        let state = BackToBackState.detect(from: [noVideoMeeting, videoMeeting], now: now)

        // Should not detect current meeting because it has no video link
        #expect(state.currentMeeting == nil)
        #expect(state.isBackToBack == false)
    }
}
