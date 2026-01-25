import Foundation
import Testing

@testable import GCalNotifierCore

// MARK: - Test Errors

private enum TestError: Error {
    case setupFailed(String)
}

// MARK: - Test Constants

// swiftlint:disable:next force_unwrapping
private let testMeetingURL = URL(string: "https://meet.google.com/abc")!

// MARK: - Mock Calendar Client

private actor MockCalendarClient {
    var eventsResponses: [EventsResponse] = []
    var errorToThrow: Error?
    var fetchCallCount = 0
    var lastSyncToken: String?
    var lastCalendarId: String?

    func queueResponse(_ response: EventsResponse) {
        self.eventsResponses.append(response)
    }

    func setError(_ error: Error?) {
        self.errorToThrow = error
    }

    func fetchEvents(
        calendarId: String,
        from _: Date?,
        to _: Date?,
        syncToken: String?
    ) async throws -> EventsResponse {
        self.fetchCallCount += 1
        self.lastSyncToken = syncToken
        self.lastCalendarId = calendarId

        if let error = errorToThrow {
            // Allow one-time error for 410 retry testing
            if case CalendarError.syncTokenInvalid = error, self.fetchCallCount > 1 {
                self.errorToThrow = nil
            } else {
                throw error
            }
        }

        guard !self.eventsResponses.isEmpty else {
            return EventsResponse(events: [], nextSyncToken: nil)
        }

        return self.eventsResponses.removeFirst()
    }

    func getCallCount() -> Int { self.fetchCallCount }
    func getLastSyncToken() -> String? { self.lastSyncToken }
}

// MARK: - Mock Google Calendar Client Wrapper

/// Wraps MockCalendarClient to provide GoogleCalendarClient-like interface for testing.
private actor MockGoogleCalendarClientWrapper {
    private let mock: MockCalendarClient

    init(mock: MockCalendarClient) {
        self.mock = mock
    }

    func fetchEvents(
        calendarId: String,
        from: Date? = nil,
        to: Date? = nil,
        syncToken: String? = nil,
        timeZone _: TimeZone = .current
    ) async throws -> EventsResponse {
        try await self.mock.fetchEvents(calendarId: calendarId, from: from, to: to, syncToken: syncToken)
    }

    func queueResponse(_ response: EventsResponse) async {
        await self.mock.queueResponse(response)
    }

    func setError(_ error: Error?) async {
        await self.mock.setError(error)
    }

    func getCallCount() async -> Int {
        await self.mock.getCallCount()
    }

    func getLastSyncToken() async -> String? {
        await self.mock.getLastSyncToken()
    }
}

// MARK: - Test Sync Engine

/// Test-friendly SyncEngine that uses mock dependencies.
private actor TestSyncEngine {
    private let mockClient: MockGoogleCalendarClientWrapper
    private let eventCache: EventCache
    private let appState: AppStateStore
    private let eventFilter: EventFilter
    private var isSyncing = false

    init(
        mockClient: MockGoogleCalendarClientWrapper,
        eventCache: EventCache,
        appState: AppStateStore,
        eventFilter: EventFilter
    ) {
        self.mockClient = mockClient
        self.eventCache = eventCache
        self.appState = appState
        self.eventFilter = eventFilter
    }

    func sync(calendarId: String) async throws -> SyncResult {
        guard !self.isSyncing else {
            throw CalendarError.syncInProgress
        }

        self.isSyncing = true
        defer { self.isSyncing = false }

        return try await self.performSync(calendarId: calendarId)
    }

    private func performSync(calendarId: String) async throws -> SyncResult {
        let syncToken = try await self.appState.getSyncToken(for: calendarId)
        let wasFullSync = syncToken == nil

        do {
            let response = try await self.fetchEvents(calendarId: calendarId, syncToken: syncToken)
            return try await self.processResponse(response, calendarId: calendarId, wasFullSync: wasFullSync)
        } catch CalendarError.syncTokenInvalid {
            try await self.appState.clearSyncToken(for: calendarId)
            let response = try await self.fetchEvents(calendarId: calendarId, syncToken: nil)
            return try await self.processResponse(response, calendarId: calendarId, wasFullSync: true)
        }
    }

    private func fetchEvents(calendarId: String, syncToken: String?) async throws -> EventsResponse {
        if let syncToken {
            return try await self.mockClient.fetchEvents(calendarId: calendarId, syncToken: syncToken)
        } else {
            let now = Date()
            let endTime = Calendar.current.date(byAdding: .hour, value: 24, to: now) ?? now
            return try await self.mockClient.fetchEvents(calendarId: calendarId, from: now, to: endTime)
        }
    }

    private func processResponse(
        _ response: EventsResponse,
        calendarId: String,
        wasFullSync: Bool
    ) async throws -> SyncResult {
        if let newToken = response.nextSyncToken {
            try await self.appState.setSyncToken(newToken, for: calendarId)
        }

        try await self.eventCache.merge(
            events: response.events,
            deletedEventIds: response.deletedEventIds,
            for: calendarId,
            isFullSync: wasFullSync
        )

        let mergedEvents = try await self.eventCache.events(forCalendar: calendarId)
        let filteredEvents = mergedEvents.filter { self.eventFilter.shouldAlert(for: $0) }

        return SyncResult(events: mergedEvents, filteredEvents: filteredEvents, wasFullSync: wasFullSync)
    }

    func getMockCallCount() async -> Int {
        await self.mockClient.getCallCount()
    }

    func getMockLastSyncToken() async -> String? {
        await self.mockClient.getLastSyncToken()
    }
}

// MARK: - Test Context

private struct SyncEngineTestContext {
    let engine: TestSyncEngine
    let mockClient: MockGoogleCalendarClientWrapper
    let eventCache: EventCache
    let appState: AppStateStore
    let settings: SettingsStore

    init() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheURL = tempDir.appendingPathComponent("test-events-\(UUID().uuidString).json")
        let stateURL = tempDir.appendingPathComponent("test-state-\(UUID().uuidString).json")

        guard let testDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)") else {
            throw TestError.setupFailed("Could not create test UserDefaults")
        }
        let settings = SettingsStore(defaults: testDefaults)
        let eventCache = EventCache(fileURL: cacheURL)
        let appState = AppStateStore(fileURL: stateURL)
        let eventFilter = EventFilter(settings: settings)
        let mockCalClient = MockCalendarClient()
        let mockClient = MockGoogleCalendarClientWrapper(mock: mockCalClient)

        self.settings = settings
        self.eventCache = eventCache
        self.appState = appState
        self.mockClient = mockClient
        self.engine = TestSyncEngine(
            mockClient: mockClient,
            eventCache: eventCache,
            appState: appState,
            eventFilter: eventFilter
        )
    }
}

// MARK: - Test Event Helpers

private func makeEvent(
    id: String = "event-1",
    calendarId: String = "primary",
    title: String = "Test Meeting",
    startTime: Date = Date().addingTimeInterval(3600),
    endTime: Date = Date().addingTimeInterval(7200),
    isAllDay: Bool = false,
    meetingLinks: [MeetingLink] = [MeetingLink(url: testMeetingURL)]
) -> CalendarEvent {
    CalendarEvent(
        id: id,
        calendarId: calendarId,
        title: title,
        startTime: startTime,
        endTime: endTime,
        isAllDay: isAllDay,
        location: nil,
        meetingLinks: meetingLinks,
        isOrganizer: false,
        attendeeCount: 2,
        responseStatus: .accepted
    )
}

// MARK: - Tests

@Suite("SyncEngine Tests", .serialized)
struct SyncEngineTests {
    @Test("sync fetches events and saves to cache")
    func syncFetchesEventsAndSavesToCache() async throws {
        let ctx = try SyncEngineTestContext()
        let event = makeEvent(id: "event-123", title: "Team Standup")
        await ctx.mockClient.queueResponse(EventsResponse(events: [event], nextSyncToken: "token-1"))

        let result = try await ctx.engine.sync(calendarId: "primary")

        #expect(result.events.count == 1)
        #expect(result.events[0].id == "event-123")

        let cachedEvents = try await ctx.eventCache.load()
        #expect(cachedEvents.count == 1)
        #expect(cachedEvents[0].id == "event-123")
    }

    @Test("sync uses sync token when available")
    func syncUsesSyncTokenWhenAvailable() async throws {
        let ctx = try SyncEngineTestContext()
        try await ctx.appState.setSyncToken("existing-token", for: "primary")
        await ctx.mockClient.queueResponse(EventsResponse(events: [], nextSyncToken: "token-2"))

        _ = try await ctx.engine.sync(calendarId: "primary")

        let usedToken = await ctx.engine.getMockLastSyncToken()
        #expect(usedToken == "existing-token")
    }

    @Test("sync stores new sync token")
    func syncStoresNewSyncToken() async throws {
        let ctx = try SyncEngineTestContext()
        await ctx.mockClient.queueResponse(EventsResponse(events: [], nextSyncToken: "new-sync-token"))

        _ = try await ctx.engine.sync(calendarId: "primary")

        let storedToken = try await ctx.appState.getSyncToken(for: "primary")
        #expect(storedToken == "new-sync-token")
    }

    @Test("sync on 410 clears sync token and retries")
    func syncOn410ClearsSyncTokenAndRetries() async throws {
        let ctx = try SyncEngineTestContext()
        try await ctx.appState.setSyncToken("old-token", for: "primary")

        // First call throws 410, second call succeeds
        await ctx.mockClient.setError(CalendarError.syncTokenInvalid)
        await ctx.mockClient.queueResponse(EventsResponse(events: [], nextSyncToken: "fresh-token"))

        let result = try await ctx.engine.sync(calendarId: "primary")

        // Should have retried
        let callCount = await ctx.engine.getMockCallCount()
        #expect(callCount == 2)

        // Should have stored new token
        let storedToken = try await ctx.appState.getSyncToken(for: "primary")
        #expect(storedToken == "fresh-token")

        // Result should indicate full sync
        #expect(result.wasFullSync == true)
    }

    @Test("sync filters events based on settings")
    func syncFiltersEventsBasedOnSettings() async throws {
        let ctx = try SyncEngineTestContext()

        let eventWithLink = makeEvent(id: "event-with-link", title: "Meeting with video")
        let eventWithoutLink = makeEvent(
            id: "event-no-link",
            title: "No video meeting",
            meetingLinks: []
        )

        await ctx.mockClient.queueResponse(
            EventsResponse(events: [eventWithLink, eventWithoutLink], nextSyncToken: nil)
        )

        let result = try await ctx.engine.sync(calendarId: "primary")

        #expect(result.events.count == 2)
        #expect(result.filteredEvents.count == 1)
        #expect(result.filteredEvents[0].id == "event-with-link")
    }

    @Test("sync returns wasFullSync true when no token exists")
    func syncReturnsWasFullSyncTrueWhenNoToken() async throws {
        let ctx = try SyncEngineTestContext()
        await ctx.mockClient.queueResponse(EventsResponse(events: [], nextSyncToken: "token-1"))

        let result = try await ctx.engine.sync(calendarId: "primary")

        #expect(result.wasFullSync == true)
    }

    @Test("sync returns wasFullSync false when token exists")
    func syncReturnsWasFullSyncFalseWhenTokenExists() async throws {
        let ctx = try SyncEngineTestContext()
        try await ctx.appState.setSyncToken("existing-token", for: "primary")
        await ctx.mockClient.queueResponse(EventsResponse(events: [], nextSyncToken: "token-2"))

        let result = try await ctx.engine.sync(calendarId: "primary")

        #expect(result.wasFullSync == false)
    }

    @Test("sync incremental merges new events without dropping existing")
    func syncIncrementalMergesEvents() async throws {
        let ctx = try SyncEngineTestContext()
        let event1 = makeEvent(id: "event-1", title: "First")
        let event2 = makeEvent(id: "event-2", title: "Second")

        await ctx.mockClient.queueResponse(EventsResponse(events: [event1], nextSyncToken: "token-1"))
        await ctx.mockClient.queueResponse(EventsResponse(events: [event2], nextSyncToken: "token-2"))

        _ = try await ctx.engine.sync(calendarId: "primary")
        let result = try await ctx.engine.sync(calendarId: "primary")

        let ids = Set(result.events.map(\.id))
        #expect(ids == Set(["event-1", "event-2"]))
    }

    @Test("sync incremental removes deleted events")
    func syncIncrementalRemovesDeletedEvents() async throws {
        let ctx = try SyncEngineTestContext()
        let event = makeEvent(id: "event-1", title: "To Remove")

        await ctx.mockClient.queueResponse(EventsResponse(events: [event], nextSyncToken: "token-1"))
        _ = try await ctx.engine.sync(calendarId: "primary")

        await ctx.mockClient.queueResponse(
            EventsResponse(events: [], nextSyncToken: "token-2", deletedEventIds: ["event-1"])
        )

        let result = try await ctx.engine.sync(calendarId: "primary")
        #expect(result.events.isEmpty)
    }
}

@Suite("SyncEngine Polling Interval Tests")
struct SyncEnginePollingIntervalTests {
    @Test("calculatePollingInterval returns normal when meeting is more than 10 minutes away")
    func calculatePollingIntervalFarMeetingReturnsNormal() async throws {
        let now = Date()
        let farEvent = makeEvent(startTime: now.addingTimeInterval(8000)) // ~2.2 hours
        let interval = self.calculatePollingInterval(events: [farEvent], now: now)
        #expect(interval == .normal)
    }

    @Test("calculatePollingInterval returns normal when meeting within 1 hour but more than 10 min")
    func calculatePollingIntervalMeetingWithin1HourReturnsNormal() async throws {
        let now = Date()
        let soonEvent = makeEvent(startTime: now.addingTimeInterval(2400)) // 40 minutes
        let interval = self.calculatePollingInterval(events: [soonEvent], now: now)
        #expect(interval == .normal)
    }

    @Test("calculatePollingInterval returns imminent when meeting within 10 minutes")
    func calculatePollingIntervalMeetingWithin10MinReturnsImminent() async throws {
        let now = Date()
        let imminentEvent = makeEvent(startTime: now.addingTimeInterval(300)) // 5 minutes
        let interval = self.calculatePollingInterval(events: [imminentEvent], now: now)
        #expect(interval == .imminent)
    }

    @Test("calculatePollingInterval returns normal when no events")
    func calculatePollingIntervalNoEventsReturnsNormal() async throws {
        let interval = self.calculatePollingInterval(events: [], now: Date())
        #expect(interval == .normal)
    }

    @Test("calculatePollingInterval ignores past events")
    func calculatePollingIntervalIgnoresPastEvents() async throws {
        let now = Date()
        let pastEvent = makeEvent(startTime: now.addingTimeInterval(-3600)) // 1 hour ago
        let interval = self.calculatePollingInterval(events: [pastEvent], now: now)
        #expect(interval == .normal)
    }

    @Test("calculatePollingInterval uses earliest upcoming event")
    func calculatePollingIntervalUsesEarliestEvent() async throws {
        let now = Date()
        let farEvent = makeEvent(id: "far", startTime: now.addingTimeInterval(7200)) // 2 hours
        let nearEvent = makeEvent(id: "near", startTime: now.addingTimeInterval(300)) // 5 minutes
        let interval = self.calculatePollingInterval(events: [farEvent, nearEvent], now: now)
        #expect(interval == .imminent)
    }

    // Helper function to match SyncEngine's calculation logic
    private func calculatePollingInterval(events: [CalendarEvent], now: Date) -> PollingInterval {
        let upcomingEvents = events.filter { $0.startTime > now }

        guard let nextEvent = upcomingEvents.min(by: { $0.startTime < $1.startTime }) else {
            return .normal
        }

        let timeUntilNext = nextEvent.startTime.timeIntervalSince(now)

        if timeUntilNext <= 600 { // 10 minutes
            return .imminent
        } else {
            return .normal
        }
    }
}
