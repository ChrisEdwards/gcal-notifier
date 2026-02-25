import Foundation
import Testing
@testable import GCalNotifier
@testable import GCalNotifierCore

// MARK: - Test Helpers

/// Creates an isolated UserDefaults suite for test isolation.
private func makeTestDefaults() -> UserDefaults {
    let suiteName = "ShortcutManagerTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        return .standard
    }
    return defaults
}

/// Creates a test event with video link.
private func makeTestEvent(
    id: String = UUID().uuidString,
    title: String = "Test Meeting",
    startTime: Date,
    endTime: Date? = nil,
    meetingURL: String = "https://meet.google.com/abc-defg-hij"
) -> CalendarEvent {
    CalendarEvent(
        id: id,
        calendarId: "primary",
        title: title,
        startTime: startTime,
        endTime: endTime ?? startTime.addingTimeInterval(3600),
        isAllDay: false,
        location: nil,
        // swiftlint:disable:next force_unwrapping
        meetingLinks: [MeetingLink(url: URL(string: meetingURL)!)],
        isOrganizer: false,
        attendeeCount: 2,
        responseStatus: .accepted
    )
}

/// Creates a test event without video link.
private func makeTestEventWithoutVideo(
    id: String = UUID().uuidString,
    title: String = "Non-Video Meeting",
    startTime: Date
) -> CalendarEvent {
    CalendarEvent(
        id: id,
        calendarId: "primary",
        title: title,
        startTime: startTime,
        endTime: startTime.addingTimeInterval(3600),
        isAllDay: false,
        location: "Room A",
        meetingLinks: [],
        isOrganizer: false,
        attendeeCount: 5,
        responseStatus: .accepted
    )
}

// MARK: - Settings Tests

@Suite("Shortcuts Settings")
struct ShortcutsSettingsTests {
    @Test("Default shortcutsEnabled is true")
    func defaultShortcutsEnabled_isTrue() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)

        #expect(store.shortcutsEnabled == true)
    }

    @Test("shortcutsEnabled persists false")
    func shortcutsEnabled_persistsFalse() {
        let defaults = makeTestDefaults()

        do {
            let store = SettingsStore(defaults: defaults)
            store.shortcutsEnabled = false
        }

        do {
            let store = SettingsStore(defaults: defaults)
            #expect(store.shortcutsEnabled == false)
        }
    }

    @Test("shortcutsEnabled persists true after toggle")
    func shortcutsEnabled_persistsAfterToggle() {
        let defaults = makeTestDefaults()

        do {
            let store = SettingsStore(defaults: defaults)
            store.shortcutsEnabled = false
            store.shortcutsEnabled = true
        }

        do {
            let store = SettingsStore(defaults: defaults)
            #expect(store.shortcutsEnabled == true)
        }
    }
}

// MARK: - Event Finding Tests

@Suite("Finding Next Meeting With Video Link")
struct FindNextMeetingTests {
    @Test("Finds event with video link starting in future")
    @MainActor
    func findsUpcomingEventWithVideo() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).json")
        let cache = EventCache(fileURL: fileURL)

        let now = Date()
        let event1 = makeTestEvent(
            id: "event1",
            title: "Meeting 1",
            startTime: now.addingTimeInterval(3600) // 1 hour from now
        )
        let event2 = makeTestEventWithoutVideo(
            id: "event2",
            title: "Meeting 2",
            startTime: now.addingTimeInterval(1800) // 30 min from now
        )

        try await cache.save([event1, event2])

        // Find events with video links starting in future
        let events = try await cache.events(from: now, to: now.addingTimeInterval(24 * 60 * 60))
        let nextWithVideo = events
            .filter { $0.hasVideoLink && $0.startTime > now }
            .sorted { $0.startTime < $1.startTime }
            .first

        #expect(nextWithVideo?.id == "event1")
    }

    @Test("Returns nil when no events have video links")
    @MainActor
    func returnsNilWhenNoVideoLinks() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).json")
        let cache = EventCache(fileURL: fileURL)

        let now = Date()
        let event1 = makeTestEventWithoutVideo(
            id: "event1",
            title: "Meeting 1",
            startTime: now.addingTimeInterval(3600)
        )

        try await cache.save([event1])

        let events = try await cache.events(from: now, to: now.addingTimeInterval(24 * 60 * 60))
        let nextWithVideo = events
            .filter { $0.hasVideoLink && $0.startTime > now }
            .first

        #expect(nextWithVideo == nil)
    }

    @Test("Skips events that have already started")
    @MainActor
    func skipsStartedEvents() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).json")
        let cache = EventCache(fileURL: fileURL)

        let now = Date()
        let pastEvent = makeTestEvent(
            id: "past",
            title: "Already Started",
            startTime: now.addingTimeInterval(-1800), // Started 30 min ago
            endTime: now.addingTimeInterval(1800) // Ends in 30 min
        )
        let futureEvent = makeTestEvent(
            id: "future",
            title: "Future Meeting",
            startTime: now.addingTimeInterval(3600) // 1 hour from now
        )

        try await cache.save([pastEvent, futureEvent])

        let events = try await cache.events(from: now, to: now.addingTimeInterval(24 * 60 * 60))
        let nextWithVideo = events
            .filter { $0.hasVideoLink && $0.startTime > now }
            .sorted { $0.startTime < $1.startTime }
            .first

        #expect(nextWithVideo?.id == "future")
    }

    @Test("Finds earliest event when multiple events have video links")
    @MainActor
    func findsEarliestEvent() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).json")
        let cache = EventCache(fileURL: fileURL)

        let now = Date()
        let event1 = makeTestEvent(
            id: "later",
            title: "Later Meeting",
            startTime: now.addingTimeInterval(7200) // 2 hours from now
        )
        let event2 = makeTestEvent(
            id: "sooner",
            title: "Sooner Meeting",
            startTime: now.addingTimeInterval(3600) // 1 hour from now
        )

        try await cache.save([event1, event2])

        let events = try await cache.events(from: now, to: now.addingTimeInterval(24 * 60 * 60))
        let nextWithVideo = events
            .filter { $0.hasVideoLink && $0.startTime > now }
            .sorted { $0.startTime < $1.startTime }
            .first

        #expect(nextWithVideo?.id == "sooner")
    }

    @Test("Skips declined events when finding next meeting")
    @MainActor
    func skipsDeclinedEvents() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).json")
        let cache = EventCache(fileURL: fileURL)

        let now = Date()
        let declinedEvent = makeTestEvent(
            id: "declined",
            title: "Declined Meeting",
            startTime: now.addingTimeInterval(1200),
            meetingURL: "https://meet.google.com/declined-meeting"
        )
        let acceptedEvent = makeTestEvent(
            id: "accepted",
            title: "Accepted Meeting",
            startTime: now.addingTimeInterval(2400),
            meetingURL: "https://meet.google.com/accepted-meeting"
        )

        let declined = CalendarEvent(
            id: declinedEvent.id,
            calendarId: declinedEvent.calendarId,
            title: declinedEvent.title,
            startTime: declinedEvent.startTime,
            endTime: declinedEvent.endTime,
            isAllDay: declinedEvent.isAllDay,
            location: declinedEvent.location,
            meetingLinks: declinedEvent.meetingLinks,
            isOrganizer: declinedEvent.isOrganizer,
            attendeeCount: declinedEvent.attendeeCount,
            responseStatus: .declined
        )

        try await cache.save([declined, acceptedEvent])

        let next = try await ShortcutManager.shared.findNextMeetingWithVideoLink(in: cache)

        #expect(next?.id == "accepted")
    }

    @Test("Skips all-day events when finding next meeting")
    @MainActor
    func skipsAllDayEvents() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).json")
        let cache = EventCache(fileURL: fileURL)

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let url = try #require(URL(string: "https://meet.google.com/all-day"))
        let allDayEvent = CalendarEvent(
            id: "all-day",
            calendarId: "primary",
            title: "All Day Meeting",
            startTime: startOfDay,
            endTime: endOfDay,
            isAllDay: true,
            location: nil,
            meetingLinks: [MeetingLink(url: url)],
            isOrganizer: false,
            attendeeCount: 1,
            responseStatus: .accepted
        )
        let regularEvent = makeTestEvent(
            id: "regular",
            title: "Regular Meeting",
            startTime: now.addingTimeInterval(3600)
        )

        try await cache.save([allDayEvent, regularEvent])

        let next = try await ShortcutManager.shared.findNextMeetingWithVideoLink(in: cache)

        #expect(next?.id == "regular")
    }

    @Test("Respects blocked keywords when settings provided")
    @MainActor
    func respectsBlockedKeywords() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).json")
        let cache = EventCache(fileURL: fileURL)

        let defaults = makeTestDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.blockedKeywords = ["Blocked"]

        let now = Date()
        let blockedEvent = makeTestEvent(
            id: "blocked",
            title: "Blocked Meeting",
            startTime: now.addingTimeInterval(1200)
        )
        let allowedEvent = makeTestEvent(
            id: "allowed",
            title: "Allowed Meeting",
            startTime: now.addingTimeInterval(2400)
        )

        try await cache.save([blockedEvent, allowedEvent])

        let next = try await ShortcutManager.shared.findNextMeetingWithVideoLink(
            in: cache,
            settings: settings
        )

        #expect(next?.id == "allowed")
    }

    @Test("Respects enabled calendars when settings provided")
    @MainActor
    func respectsEnabledCalendars() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).json")
        let cache = EventCache(fileURL: fileURL)

        let defaults = makeTestDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.enabledCalendars = ["work"]

        let now = Date()
        let url = try #require(URL(string: "https://meet.google.com/test"))
        let disabledCalendarEvent = CalendarEvent(
            id: "personal",
            calendarId: "personal",
            title: "Personal Meeting",
            startTime: now.addingTimeInterval(1200),
            endTime: now.addingTimeInterval(1800),
            isAllDay: false,
            location: nil,
            meetingLinks: [MeetingLink(url: url)],
            isOrganizer: false,
            attendeeCount: 2,
            responseStatus: .accepted
        )
        let enabledCalendarEvent = CalendarEvent(
            id: "work",
            calendarId: "work",
            title: "Work Meeting",
            startTime: now.addingTimeInterval(2400),
            endTime: now.addingTimeInterval(3000),
            isAllDay: false,
            location: nil,
            meetingLinks: [MeetingLink(url: url)],
            isOrganizer: false,
            attendeeCount: 2,
            responseStatus: .accepted
        )

        try await cache.save([disabledCalendarEvent, enabledCalendarEvent])

        let next = try await ShortcutManager.shared.findNextMeetingWithVideoLink(
            in: cache,
            settings: settings
        )

        #expect(next?.id == "work")
    }
}

// MARK: - Event Extension Tests

@Suite("CalendarEvent Video Link Detection")
struct CalendarEventVideoLinkTests {
    @Test("hasVideoLink returns true for event with meeting links")
    func hasVideoLink_trueForEventWithLinks() {
        let event = makeTestEvent(title: "Video Meeting", startTime: Date())

        #expect(event.hasVideoLink == true)
    }

    @Test("hasVideoLink returns false for event without meeting links")
    func hasVideoLink_falseForEventWithoutLinks() {
        let event = makeTestEventWithoutVideo(title: "In-Person Meeting", startTime: Date())

        #expect(event.hasVideoLink == false)
    }

    @Test("primaryMeetingURL returns first URL")
    func primaryMeetingURL_returnsFirstURL() {
        let event = makeTestEvent(
            title: "Video Meeting",
            startTime: Date(),
            meetingURL: "https://meet.google.com/test-meeting"
        )

        #expect(event.primaryMeetingURL?.absoluteString == "https://meet.google.com/test-meeting")
    }

    @Test("primaryMeetingURL returns nil for event without links")
    func primaryMeetingURL_nilForNoLinks() {
        let event = makeTestEventWithoutVideo(title: "No Video", startTime: Date())

        #expect(event.primaryMeetingURL == nil)
    }
}
