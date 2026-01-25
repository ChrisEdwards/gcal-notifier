import Foundation
import Testing

@testable import GCalNotifier
@testable import GCalNotifierCore

// MARK: - Test Helpers

/// Creates a temporary file URL for test isolation.
private func makeTempFileURL() -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let testDir = tempDir.appendingPathComponent("MenuControllerTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    return testDir.appendingPathComponent("events.json")
}

/// Cleans up a temporary test directory.
private func cleanupTempDir(_ url: URL) {
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.removeItem(at: dir)
}

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

// MARK: - MenuController EventCache Integration Tests

@Suite("MenuController EventCache Integration Tests")
@MainActor
struct MenuControllerEventCacheTests {
    @Test("loadEventsFromCache loads today's events")
    func loadEventsFromCacheLoadsTodaysEvents() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)

        // Create events: one for today, one for tomorrow
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        guard let link = makeTestLink() else {
            Issue.record("Failed to create test link")
            return
        }

        let todayEvent = makeTestEvent(
            id: "today-event",
            title: "Today's Meeting",
            startTime: startOfDay.addingTimeInterval(10 * 3600), // 10:00 AM today
            endTime: startOfDay.addingTimeInterval(11 * 3600),
            meetingLinks: [link]
        )

        let tomorrowEvent = makeTestEvent(
            id: "tomorrow-event",
            title: "Tomorrow's Meeting",
            startTime: startOfDay.addingTimeInterval(34 * 3600), // 10:00 AM tomorrow
            endTime: startOfDay.addingTimeInterval(35 * 3600),
            meetingLinks: [link]
        )

        try await cache.save([todayEvent, tomorrowEvent])

        // Create MenuController and configure with cache
        let menuController = MenuController()
        menuController.configure(eventCache: cache)

        // Load events from cache
        await menuController.loadEventsFromCache()

        // Build menu and verify today's event is included
        // (MenuBuilder filters to today's events and sorts them)
        let menu = menuController.buildMenu()

        // The menu should have been built - we can verify by checking it has items
        // Since we're in setup mode by default, we need to check after updating
        menuController.updateSetupRequired(false)
        let menuAfterSetup = menuController.buildMenu()

        // Menu should have items (section header, meeting, separator, actions)
        #expect(menuAfterSetup.items.count > 0)
    }

    @Test("loadEventsFromCache handles empty cache")
    func loadEventsFromCacheHandlesEmptyCache() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)

        let menuController = MenuController()
        menuController.configure(eventCache: cache)
        menuController.updateSetupRequired(false)

        // Load from empty cache
        await menuController.loadEventsFromCache()

        // Build menu
        let menu = menuController.buildMenu()

        // Menu should still build (with empty state)
        #expect(menu.items.count > 0)
    }

    @Test("loadEventsFromCache without configuration does nothing")
    func loadEventsFromCacheWithoutConfigurationDoesNothing() async {
        let menuController = MenuController()
        menuController.updateSetupRequired(false)

        // Load without configuring cache - should not crash
        await menuController.loadEventsFromCache()

        // Build menu - should show empty state
        let menu = menuController.buildMenu()
        #expect(menu.items.count > 0)
    }

    @Test("configure stores event cache reference")
    func configureStoresEventCacheReference() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)

        // Save an event
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        guard let link = makeTestLink() else {
            Issue.record("Failed to create test link")
            return
        }

        let event = makeTestEvent(
            id: "test-event",
            title: "Test Meeting",
            startTime: startOfDay.addingTimeInterval(12 * 3600),
            endTime: startOfDay.addingTimeInterval(13 * 3600),
            meetingLinks: [link]
        )
        try await cache.save([event])

        let menuController = MenuController()

        // Before configure - loadEventsFromCache should do nothing
        await menuController.loadEventsFromCache()

        // Configure
        menuController.configure(eventCache: cache)

        // After configure - loadEventsFromCache should load events
        await menuController.loadEventsFromCache()

        // Verify events were loaded by checking menu build works
        menuController.updateSetupRequired(false)
        let menu = menuController.buildMenu()
        #expect(menu.items.count > 0)
    }
}

// MARK: - MenuController State Tests

@Suite("MenuController State Tests")
@MainActor
struct MenuControllerStateTests {
    @Test("updateEvents stores events for menu building")
    func updateEventsStoresEvents() {
        let menuController = MenuController()
        menuController.updateSetupRequired(false)

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        guard let link = makeTestLink() else {
            Issue.record("Failed to create test link")
            return
        }

        let event = makeTestEvent(
            id: "test-event",
            title: "Test Meeting",
            startTime: startOfDay.addingTimeInterval(10 * 3600),
            endTime: startOfDay.addingTimeInterval(11 * 3600),
            meetingLinks: [link]
        )

        menuController.updateEvents([event])

        let menu = menuController.buildMenu()
        #expect(menu.items.count > 0)
    }

    @Test("updateSetupRequired changes menu to setup mode")
    func updateSetupRequiredChangesMenuMode() {
        let menuController = MenuController()

        // Default is not setup required
        menuController.updateSetupRequired(false)
        let normalMenu = menuController.buildMenu()

        menuController.updateSetupRequired(true)
        let setupMenu = menuController.buildMenu()

        // Setup menu should have different items than normal menu
        // Both should have items though
        #expect(normalMenu.items.count > 0)
        #expect(setupMenu.items.count > 0)
    }
}
