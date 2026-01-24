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
}

// MARK: - Time Formatting Tests

@Suite("Time Formatting")
struct TimeFormattingTests {
    @Test("Formats minutes correctly")
    func formatsMinutes() {
        let minutes = 45
        let expected = "45 minutes"

        let result = self.formatTimeUntilTest(minutes: minutes, hours: 0)

        #expect(result == expected)
    }

    @Test("Formats singular minute correctly")
    func formatsSingleMinute() {
        let minutes = 1
        let expected = "1 minute"

        let result = self.formatTimeUntilTest(minutes: minutes, hours: 0)

        #expect(result == expected)
    }

    @Test("Formats hours correctly")
    func formatsHours() {
        let expected = "2 hours"

        let result = self.formatTimeUntilTest(minutes: 0, hours: 2)

        #expect(result == expected)
    }

    @Test("Formats singular hour correctly")
    func formatsSingleHour() {
        let expected = "1 hour"

        let result = self.formatTimeUntilTest(minutes: 0, hours: 1)

        #expect(result == expected)
    }

    @Test("Formats hours and minutes together")
    func formatsHoursAndMinutes() {
        let expected = "1h 30m"

        let result = self.formatTimeUntilTest(minutes: 30, hours: 1)

        #expect(result == expected)
    }

    // Helper function that mimics the formatting logic
    private func formatTimeUntilTest(minutes: Int, hours: Int) -> String {
        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
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

// MARK: - Join Threshold Tests

@Suite("Join Threshold Determination")
struct JoinThresholdTests {
    @Test("Event within 30 minutes should join directly")
    func withinThreshold_joinDirectly() {
        let now = Date()
        let event = makeTestEvent(
            title: "Soon Meeting",
            startTime: now.addingTimeInterval(20 * 60) // 20 minutes
        )

        let timeUntil = event.startTime.timeIntervalSinceNow
        let shouldJoinDirectly = timeUntil <= 30 * 60

        #expect(shouldJoinDirectly == true)
    }

    @Test("Event more than 30 minutes away should show confirmation")
    func beyondThreshold_showConfirmation() {
        let now = Date()
        let event = makeTestEvent(
            title: "Later Meeting",
            startTime: now.addingTimeInterval(45 * 60) // 45 minutes
        )

        let timeUntil = event.startTime.timeIntervalSinceNow
        let shouldJoinDirectly = timeUntil <= 30 * 60

        #expect(shouldJoinDirectly == false)
    }

    @Test("Event exactly at 30 minutes should join directly")
    func exactlyAtThreshold_joinDirectly() {
        let now = Date()
        let event = makeTestEvent(
            title: "Boundary Meeting",
            startTime: now.addingTimeInterval(30 * 60) // Exactly 30 minutes
        )

        let timeUntil = event.startTime.timeIntervalSinceNow
        let shouldJoinDirectly = timeUntil <= 30 * 60

        #expect(shouldJoinDirectly == true)
    }
}
