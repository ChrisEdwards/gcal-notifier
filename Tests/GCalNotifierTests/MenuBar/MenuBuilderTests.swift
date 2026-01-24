import Foundation
import Testing

@testable import GCalNotifier
@testable import GCalNotifierCore

// MARK: - Test Helpers

/// Creates a test CalendarEvent with default values.
private func makeTestEvent(
    id: String = "test-event-1",
    calendarId: String = "primary",
    title: String = "Test Meeting",
    startTime: Date = Date().addingTimeInterval(3600),
    endTime: Date = Date().addingTimeInterval(7200),
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

/// Creates a MeetingLink for testing.
private func makeTestLink(urlString: String = "https://meet.google.com/abc-defg-hij") -> MeetingLink? {
    guard let url = URL(string: urlString) else { return nil }
    return MeetingLink(url: url)
}

// MARK: - MenuBuilder Tests

@Suite("MenuBuilder Tests")
struct MenuBuilderTests {
    // MARK: - Notification Permission Warning

    @Test("Shows notification warning when permission denied")
    func showsNotificationWarningWhenDenied() {
        let items = MenuBuilder.buildMenuItems(
            events: [],
            conflictingEventIds: [],
            notificationPermissionDenied: true
        )

        guard case .notificationWarning = items[0] else {
            Issue.record("Expected notificationWarning item first")
            return
        }
        #expect(items[1] == .separator)
    }

    @Test("No notification warning when permission granted")
    func noNotificationWarningWhenGranted() {
        let items = MenuBuilder.buildMenuItems(
            events: [],
            conflictingEventIds: [],
            notificationPermissionDenied: false
        )

        let hasWarning = items.contains { if case .notificationWarning = $0 { return true }; return false }
        #expect(!hasWarning)
    }

    @Test("Notification warning appears before quick join")
    func notificationWarningAppearsBeforeQuickJoin() {
        let now = Date()
        guard let link = makeTestLink() else { return }
        let event = makeTestEvent(
            id: "next-meeting",
            startTime: now.addingTimeInterval(30 * 60),
            meetingLinks: [link]
        )

        let items = MenuBuilder.buildMenuItems(
            events: [event],
            conflictingEventIds: [],
            notificationPermissionDenied: true,
            now: now
        )

        guard case .notificationWarning = items[0] else {
            Issue.record("Expected notificationWarning item first")
            return
        }
        #expect(items[1] == .separator)
        guard case .quickJoin = items[2] else {
            Issue.record("Expected quickJoin after warning")
            return
        }
    }

    // MARK: - Quick Join

    @Test("Builds menu with quick join when next meeting has link")
    func buildsQuickJoinSection() {
        let now = Date()
        guard let link = makeTestLink() else {
            Issue.record("Failed to create test link")
            return
        }
        let event = makeTestEvent(
            id: "next-meeting",
            title: "Standup",
            startTime: now.addingTimeInterval(30 * 60),
            meetingLinks: [link]
        )

        let items = MenuBuilder.buildMenuItems(events: [event], conflictingEventIds: [], now: now)

        guard case let .quickJoin(title, qjEvent) = items[0] else {
            Issue.record("Expected quickJoin item first")
            return
        }
        #expect(title == "Standup")
        #expect(qjEvent.id == "next-meeting")
        #expect(items[1] == .separator)
    }

    @Test("Skips quick join when no meetings have links")
    func skipsQuickJoinWithoutLinks() {
        let now = Date()
        let event = makeTestEvent(startTime: now.addingTimeInterval(30 * 60), meetingLinks: [])

        let items = MenuBuilder.buildMenuItems(events: [event], conflictingEventIds: [], now: now)

        guard case .sectionHeader = items[0] else {
            Issue.record("Expected sectionHeader first when no quick join")
            return
        }
    }

    @Test("Shows conflict warning when conflicts exist")
    func showsConflictWarning() {
        let now = Date()
        guard let link = makeTestLink() else { return }
        let event1 = makeTestEvent(id: "event1", startTime: now.addingTimeInterval(60 * 60), meetingLinks: [link])
        let event2 = makeTestEvent(id: "event2", startTime: now.addingTimeInterval(60 * 60), meetingLinks: [link])

        let items = MenuBuilder.buildMenuItems(
            events: [event1, event2],
            conflictingEventIds: ["event1", "event2"],
            now: now
        )

        let hasConflictWarning = items.contains { if case .conflictWarning = $0 { return true }; return false }
        #expect(hasConflictWarning)
    }

    @Test("Shows empty state when no meetings today")
    func showsEmptyState() {
        let items = MenuBuilder.buildMenuItems(events: [], conflictingEventIds: [])
        let hasEmptyState = items
            .contains { if case let .emptyState(msg) = $0 { return msg == "No meetings today" }; return false }
        #expect(hasEmptyState)
    }

    @Test("Shows today's meetings header")
    func showsTodaysMeetingsHeader() {
        let items = MenuBuilder.buildMenuItems(events: [], conflictingEventIds: [])
        let hasHeader = items
            .contains { if case let .sectionHeader(title) = $0 { return title == "Today's Meetings" }; return false }
        #expect(hasHeader)
    }

    @Test("Includes all action items")
    func includesActionItems() {
        let items = MenuBuilder.buildMenuItems(events: [], conflictingEventIds: [])
        let hasRefresh = items
            .contains { if case let .action(t, a) = $0 { return t == "Refresh Now" && a == .refresh }; return false }
        let hasSettings = items
            .contains { if case let .action(t, a) = $0 { return t == "Settings..." && a == .settings }; return false }
        let hasQuit = items
            .contains { if case let .action(t, a) = $0 { return t == "Quit gcal-notifier" && a == .quit }; return false
            }
        #expect(hasRefresh)
        #expect(hasSettings)
        #expect(hasQuit)
    }
}

// MARK: - Meeting Item Tests

@Suite("Meeting Item Tests")
struct MeetingItemTests {
    @Test("Meeting with link shows checkmark icon and is enabled")
    func meetingWithLinkShowsCheckmark() {
        let now = Date()
        guard let link = makeTestLink() else { return }
        let event = makeTestEvent(startTime: now.addingTimeInterval(60 * 60), meetingLinks: [link])
        let items = MenuBuilder.buildMenuItems(events: [event], conflictingEventIds: [], now: now)
        let meetingItem = items.first { if case .meeting = $0 { return true }; return false }

        guard case let .meeting(icon, _, _, _, enabled) = meetingItem else {
            Issue.record("Expected meeting item")
            return
        }
        #expect(icon == "v")
        #expect(enabled == true)
    }

    @Test("Meeting without link shows circle icon and is disabled")
    func meetingWithoutLinkShowsCircle() {
        let now = Date()
        let event = makeTestEvent(startTime: now.addingTimeInterval(60 * 60), meetingLinks: [])
        let items = MenuBuilder.buildMenuItems(events: [event], conflictingEventIds: [], now: now)
        let meetingItem = items.first { if case .meeting = $0 { return true }; return false }

        guard case let .meeting(icon, _, _, _, enabled) = meetingItem else {
            Issue.record("Expected meeting item")
            return
        }
        #expect(icon == "o")
        #expect(enabled == false)
    }

    @Test("Conflicting meeting shows exclamation icon")
    func conflictingMeetingShowsExclamation() {
        let now = Date()
        guard let link = makeTestLink() else { return }
        let event = makeTestEvent(id: "conflicting", startTime: now.addingTimeInterval(60 * 60), meetingLinks: [link])
        let items = MenuBuilder.buildMenuItems(events: [event], conflictingEventIds: ["conflicting"], now: now)
        let meetingItem = items.first { if case .meeting = $0 { return true }; return false }

        guard case let .meeting(icon, _, _, _, _) = meetingItem else {
            Issue.record("Expected meeting item")
            return
        }
        #expect(icon == "!")
    }

    @Test("Meeting title truncated to 25 characters")
    func meetingTitleTruncated() {
        let now = Date()
        guard let link = makeTestLink() else { return }
        let longTitle = "This is a very long meeting title that exceeds twenty five characters"
        let event = makeTestEvent(title: longTitle, startTime: now.addingTimeInterval(60 * 60), meetingLinks: [link])
        let items = MenuBuilder.buildMenuItems(events: [event], conflictingEventIds: [], now: now)
        let meetingItem = items.first { if case .meeting = $0 { return true }; return false }

        guard case let .meeting(_, title, _, _, _) = meetingItem else {
            Issue.record("Expected meeting item")
            return
        }
        #expect(title.count == 25)
        #expect(title == "This is a very long meeti")
    }
}

// MARK: - Event Filtering Tests

@Suite("Menu Event Filtering Tests")
struct MenuEventFilteringTests {
    @Test("Filters out all-day events")
    func filtersAllDayEvents() {
        let now = Date()
        guard let link = makeTestLink() else { return }
        let allDayEvent = makeTestEvent(
            id: "all-day",
            startTime: now.addingTimeInterval(60 * 60),
            isAllDay: true,
            meetingLinks: [link]
        )
        let regularEvent = makeTestEvent(
            id: "regular",
            startTime: now.addingTimeInterval(60 * 60),
            meetingLinks: [link]
        )
        let items = MenuBuilder.buildMenuItems(events: [allDayEvent, regularEvent], conflictingEventIds: [], now: now)
        let meetingItems = items.filter { if case .meeting = $0 { return true }; return false }

        #expect(meetingItems.count == 1)
        guard case let .meeting(_, _, _, event, _) = meetingItems[0] else { return }
        #expect(event.id == "regular")
    }

    @Test("Filters out events from other days")
    func filtersOtherDayEvents() {
        let now = Date()
        guard let link = makeTestLink() else { return }
        let tomorrowEvent = makeTestEvent(
            id: "tomorrow",
            startTime: now.addingTimeInterval(24 * 60 * 60),
            meetingLinks: [link]
        )
        let todayEvent = makeTestEvent(id: "today", startTime: now.addingTimeInterval(60 * 60), meetingLinks: [link])
        let items = MenuBuilder.buildMenuItems(events: [tomorrowEvent, todayEvent], conflictingEventIds: [], now: now)
        let meetingItems = items.filter { if case .meeting = $0 { return true }; return false }

        #expect(meetingItems.count == 1)
    }

    @Test("Sorts events by start time")
    func sortsByStartTime() {
        // Use morning time to avoid midnight boundary issues
        let calendar = Calendar.current
        guard let now = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) else { return }
        guard let link = makeTestLink() else { return }
        let laterEvent = makeTestEvent(
            id: "later",
            title: "Later Meeting",
            startTime: now.addingTimeInterval(120 * 60), // 11:00 AM
            meetingLinks: [link]
        )
        let soonerEvent = makeTestEvent(
            id: "sooner",
            title: "Sooner Meeting",
            startTime: now.addingTimeInterval(30 * 60), // 9:30 AM
            meetingLinks: [link]
        )
        let items = MenuBuilder.buildMenuItems(events: [laterEvent, soonerEvent], conflictingEventIds: [], now: now)
        let meetingItems = items.filter { if case .meeting = $0 { return true }; return false }

        #expect(meetingItems.count >= 2, "Expected at least 2 meeting items, got \(meetingItems.count)")
        guard meetingItems.count >= 2 else { return }

        guard case let .meeting(_, title1, _, _, _) = meetingItems[0],
              case let .meeting(_, title2, _, _, _) = meetingItems[1] else { return }

        #expect(title1 == "Sooner Meeting")
        #expect(title2 == "Later Meeting")
    }

    @Test("Quick join picks next future meeting with link")
    func quickJoinPicksNextFuture() {
        let now = Date()
        guard let link = makeTestLink() else { return }
        let pastEvent = makeTestEvent(
            id: "past",
            title: "Past",
            startTime: now.addingTimeInterval(-30 * 60),
            meetingLinks: [link]
        )
        let futureEvent = makeTestEvent(
            id: "future",
            title: "Future Meeting",
            startTime: now.addingTimeInterval(30 * 60),
            meetingLinks: [link]
        )
        let items = MenuBuilder.buildMenuItems(events: [pastEvent, futureEvent], conflictingEventIds: [], now: now)

        guard case let .quickJoin(title, _) = items[0] else {
            Issue.record("Expected quickJoin item first")
            return
        }
        #expect(title == "Future Meeting")
    }
}

// MARK: - Countdown Formatting Tests

@Suite("Menu Countdown Formatting Tests")
struct MenuCountdownFormattingTests {
    @Test("Formats countdown correctly")
    func formatsCountdownCorrectly() {
        let now = Date()
        let event = makeTestEvent(startTime: now.addingTimeInterval(32 * 60))
        let countdown = MenuBuilder.formatCountdown(to: event, now: now)
        #expect(countdown == "32m")
    }

    @Test("Formats countdown with hours")
    func formatsCountdownWithHours() {
        let now = Date()
        let event = makeTestEvent(startTime: now.addingTimeInterval(90 * 60))
        let countdown = MenuBuilder.formatCountdown(to: event, now: now)
        #expect(countdown == "1h 30m")
    }

    @Test("Shows 'now' for past events")
    func showsNowForPastEvents() {
        let now = Date()
        let event = makeTestEvent(startTime: now.addingTimeInterval(-5 * 60))
        let countdown = MenuBuilder.formatCountdown(to: event, now: now)
        #expect(countdown == "now")
    }
}

// MARK: - MenuItem Equatable Tests

@Suite("MenuItem Equatable Tests")
struct MenuItemEquatableTests {
    @Test("Notification warning items are equal")
    func notificationWarningsAreEqual() {
        #expect(MenuBuilder.MenuItem.notificationWarning == MenuBuilder.MenuItem.notificationWarning)
    }

    @Test("Separator items are equal")
    func separatorsAreEqual() {
        #expect(MenuBuilder.MenuItem.separator == MenuBuilder.MenuItem.separator)
    }

    @Test("Action items with same values are equal")
    func actionItemsEqual() {
        let item1 = MenuBuilder.MenuItem.action(title: "Refresh", action: .refresh)
        let item2 = MenuBuilder.MenuItem.action(title: "Refresh", action: .refresh)
        #expect(item1 == item2)
    }

    @Test("Action items with different actions are not equal")
    func actionItemsNotEqual() {
        let item1 = MenuBuilder.MenuItem.action(title: "Refresh", action: .refresh)
        let item2 = MenuBuilder.MenuItem.action(title: "Refresh", action: .settings)
        #expect(item1 != item2)
    }

    @Test("Empty state items with same message are equal")
    func emptyStateItemsEqual() {
        let item1 = MenuBuilder.MenuItem.emptyState(message: "No meetings")
        let item2 = MenuBuilder.MenuItem.emptyState(message: "No meetings")
        #expect(item1 == item2)
    }

    @Test("OpenNotificationSettings action items are equal")
    func openNotificationSettingsActionItemsEqual() {
        let item1 = MenuBuilder.MenuItem.action(title: "Open Settings", action: .openNotificationSettings)
        let item2 = MenuBuilder.MenuItem.action(title: "Open Settings", action: .openNotificationSettings)
        #expect(item1 == item2)
    }
}
