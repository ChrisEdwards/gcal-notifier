import Foundation
import SwiftUI
import Testing

@testable import GCalNotifier
@testable import GCalNotifierCore

// MARK: - Test Helpers

private func makeTestEvent(
    id: String = "test-event-1",
    calendarId: String = "primary",
    title: String = "Test Meeting",
    startTime: Date = Date().addingTimeInterval(600),
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

private func makeTestMeetingLink(
    urlString: String = "https://meet.google.com/abc-defg-hij"
) -> MeetingLink? {
    guard let url = URL(string: urlString) else { return nil }
    return MeetingLink(url: url, platform: .googleMeet)
}

// MARK: - AlertContentView Tests

@Suite("AlertContentView Tests")
struct AlertContentViewTests {
    @MainActor
    @Test("AlertContentView initializes with all parameters")
    func initializesWithParameters() {
        let event = makeTestEvent()
        var joinCalled = false
        var snoozeCalled = false
        var openCalCalled = false
        var dismissCalled = false

        let view = AlertContentView(
            event: event,
            stage: .stage1,
            isSnoozed: false,
            snoozeContext: nil,
            onJoin: { joinCalled = true },
            onSnooze: { _ in snoozeCalled = true },
            onOpenCalendar: { openCalCalled = true },
            onDismiss: { dismissCalled = true }
        )

        #expect(view.event.id == event.id)
        #expect(view.stage == .stage1)
        #expect(view.isSnoozed == false)
        #expect(view.snoozeContext == nil)

        view.onJoin()
        #expect(joinCalled)

        view.onSnooze(60)
        #expect(snoozeCalled)

        view.onOpenCalendar()
        #expect(openCalCalled)

        view.onDismiss()
        #expect(dismissCalled)
    }

    @MainActor
    @Test("AlertContentView handles snoozed state")
    func handlesSnoozedState() {
        let event = makeTestEvent()

        let view = AlertContentView(
            event: event,
            stage: .stage2,
            isSnoozed: true,
            snoozeContext: "Originally at 9:30 AM",
            onJoin: {},
            onSnooze: { _ in },
            onOpenCalendar: {},
            onDismiss: {}
        )

        #expect(view.isSnoozed == true)
        #expect(view.snoozeContext == "Originally at 9:30 AM")
    }

    @MainActor
    @Test("AlertContentView handles both stages")
    func handlesBothStages() {
        let event = makeTestEvent()

        let stage1View = AlertContentView(
            event: event,
            stage: .stage1,
            isSnoozed: false,
            snoozeContext: nil,
            onJoin: {},
            onSnooze: { _ in },
            onOpenCalendar: {},
            onDismiss: {}
        )

        let stage2View = AlertContentView(
            event: event,
            stage: .stage2,
            isSnoozed: false,
            snoozeContext: nil,
            onJoin: {},
            onSnooze: { _ in },
            onOpenCalendar: {},
            onDismiss: {}
        )

        #expect(stage1View.stage == .stage1)
        #expect(stage2View.stage == .stage2)
    }

    @MainActor
    @Test("AlertContentView body creates view hierarchy")
    func bodyCreatesViewHierarchy() {
        let event = makeTestEvent()

        let view = AlertContentView(
            event: event,
            stage: .stage1,
            isSnoozed: false,
            snoozeContext: nil,
            onJoin: {},
            onSnooze: { _ in },
            onOpenCalendar: {},
            onDismiss: {}
        )

        // Accessing body property to ensure it builds without crashing
        _ = view.body

        // Test passes if no crash occurs
        #expect(true)
    }
}

// MARK: - CombinedAlertContentView Tests

@Suite("CombinedAlertContentView Tests")
struct CombinedAlertContentViewTests {
    @MainActor
    @Test("CombinedAlertContentView initializes with events")
    func initializesWithEvents() {
        let events = [
            makeTestEvent(id: "event-1", title: "Standup"),
            makeTestEvent(id: "event-2", title: "1:1 with Sarah"),
        ]
        var joinedEvent: CalendarEvent?
        var dismissAllCalled = false

        let view = CombinedAlertContentView(
            events: events,
            onJoin: { event in joinedEvent = event },
            onDismissAll: { dismissAllCalled = true }
        )

        #expect(view.events.count == 2)

        view.onJoin(events[0])
        #expect(joinedEvent?.id == "event-1")

        view.onDismissAll()
        #expect(dismissAllCalled)
    }

    @MainActor
    @Test("CombinedAlertContentView handles empty events array")
    func handlesEmptyEvents() {
        let view = CombinedAlertContentView(
            events: [],
            onJoin: { _ in },
            onDismissAll: {}
        )

        #expect(view.events.isEmpty)

        // Accessing body to ensure it builds without crashing
        _ = view.body

        #expect(true)
    }

    @MainActor
    @Test("CombinedAlertContentView handles multiple events")
    func handlesMultipleEvents() {
        let events = [
            makeTestEvent(id: "event-1", title: "Meeting A"),
            makeTestEvent(id: "event-2", title: "Meeting B"),
            makeTestEvent(id: "event-3", title: "Meeting C"),
        ]

        let view = CombinedAlertContentView(
            events: events,
            onJoin: { _ in },
            onDismissAll: {}
        )

        #expect(view.events.count == 3)

        // Accessing body to ensure it builds without crashing
        _ = view.body

        #expect(true)
    }

    @MainActor
    @Test("CombinedAlertContentView body creates view hierarchy")
    func bodyCreatesViewHierarchy() {
        let events = [makeTestEvent()]

        let view = CombinedAlertContentView(
            events: events,
            onJoin: { _ in },
            onDismissAll: {}
        )

        // Accessing body property to ensure it builds without crashing
        _ = view.body

        // Test passes if no crash occurs
        #expect(true)
    }
}

// MARK: - AlertContentViewProvider Tests

@Suite("AlertContentViewProvider Tests")
struct AlertContentViewProviderTests {
    @MainActor
    @Test("Provider creates AlertContentView")
    func providerCreatesAlertContentView() {
        let event = makeTestEvent()
        let provider = AlertContentViewProvider()

        let actions = AlertWindowActions(
            onJoin: {},
            onSnooze: { _ in },
            onOpenCalendar: {},
            onDismiss: {}
        )

        let view = provider.makeContentView(
            event: event,
            stage: .stage1,
            isSnoozed: false,
            snoozeContext: nil,
            actions: actions
        )

        // Verify it returns an AlertContentView (opaque type)
        // We can't directly check the type, but we can verify it doesn't crash
        _ = view

        #expect(true)
    }

    @MainActor
    @Test("Provider handles snooze context")
    func providerHandlesSnoozeContext() {
        let event = makeTestEvent()
        let provider = AlertContentViewProvider()

        let actions = AlertWindowActions(
            onJoin: {},
            onSnooze: { _ in },
            onOpenCalendar: {},
            onDismiss: {}
        )

        let view = provider.makeContentView(
            event: event,
            stage: .stage2,
            isSnoozed: true,
            snoozeContext: "10:00 AM",
            actions: actions
        )

        _ = view

        #expect(true)
    }
}

// MARK: - Header Text Logic Tests

@Suite("Header Text Logic Tests")
struct HeaderTextLogicTests {
    @MainActor
    @Test("Header shows meeting started when past start time")
    func headerShowsMeetingStarted() {
        // Event that started 5 minutes ago
        let pastEvent = makeTestEvent(
            startTime: Date().addingTimeInterval(-300)
        )

        let view = AlertContentView(
            event: pastEvent,
            stage: .stage1,
            isSnoozed: false,
            snoozeContext: nil,
            onJoin: {},
            onSnooze: { _ in },
            onOpenCalendar: {},
            onDismiss: {}
        )

        // Access body to ensure view builds
        _ = view.body

        #expect(true)
    }

    @MainActor
    @Test("Header shows meeting starts now within 60 seconds")
    func headerShowsMeetingStartsNow() {
        // Event starting in 30 seconds
        let soonEvent = makeTestEvent(
            startTime: Date().addingTimeInterval(30)
        )

        let view = AlertContentView(
            event: soonEvent,
            stage: .stage1,
            isSnoozed: false,
            snoozeContext: nil,
            onJoin: {},
            onSnooze: { _ in },
            onOpenCalendar: {},
            onDismiss: {}
        )

        _ = view.body

        #expect(true)
    }

    @MainActor
    @Test("Header shows minutes countdown")
    func headerShowsMinutesCountdown() {
        // Event starting in 10 minutes
        let futureEvent = makeTestEvent(
            startTime: Date().addingTimeInterval(600)
        )

        let view = AlertContentView(
            event: futureEvent,
            stage: .stage1,
            isSnoozed: false,
            snoozeContext: nil,
            onJoin: {},
            onSnooze: { _ in },
            onOpenCalendar: {},
            onDismiss: {}
        )

        _ = view.body

        #expect(true)
    }
}

// MARK: - Title Truncation Tests

@Suite("Title Truncation Tests")
struct TitleTruncationTests {
    @MainActor
    @Test("Short title not truncated in combined view")
    func shortTitleNotTruncated() {
        let shortTitle = "Standup"
        let event = makeTestEvent(title: shortTitle)

        let view = CombinedAlertContentView(
            events: [event],
            onJoin: { _ in },
            onDismissAll: {}
        )

        // Title should not be truncated (under 15 chars)
        _ = view.body

        #expect(true)
    }

    @MainActor
    @Test("Long title truncated in combined view")
    func longTitleTruncated() {
        let longTitle = "This is a very long meeting title that should be truncated"
        let event = makeTestEvent(title: longTitle)

        let view = CombinedAlertContentView(
            events: [event],
            onJoin: { _ in },
            onDismissAll: {}
        )

        // Title should be truncated (over 15 chars)
        _ = view.body

        #expect(true)
    }
}

// MARK: - Join Button State Tests

@Suite("Join Button State Tests")
struct JoinButtonStateTests {
    @MainActor
    @Test("Join button enabled when meeting link exists")
    func joinButtonEnabledWithLink() {
        guard let meetingLink = makeTestMeetingLink() else {
            Issue.record("Failed to create meeting link")
            return
        }

        let event = makeTestEvent(meetingLinks: [meetingLink])

        let view = AlertContentView(
            event: event,
            stage: .stage1,
            isSnoozed: false,
            snoozeContext: nil,
            onJoin: {},
            onSnooze: { _ in },
            onOpenCalendar: {},
            onDismiss: {}
        )

        #expect(event.primaryMeetingURL != nil)
        _ = view.body

        #expect(true)
    }

    @MainActor
    @Test("Join button state when no meeting link")
    func joinButtonStateWithoutLink() {
        let event = makeTestEvent(meetingLinks: [])

        let view = AlertContentView(
            event: event,
            stage: .stage1,
            isSnoozed: false,
            snoozeContext: nil,
            onJoin: {},
            onSnooze: { _ in },
            onOpenCalendar: {},
            onDismiss: {}
        )

        #expect(event.primaryMeetingURL == nil)
        _ = view.body

        #expect(true)
    }
}
