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

// MARK: - Multi-Calendar Mock Client

/// Mock that supports per-calendar responses and errors for multi-calendar testing.
private actor MultiCalendarMockClient {
    private var responsesByCalendar: [String: [EventsResponse]] = [:]
    private var errorsByCalendar: [String: Error] = [:]
    var fetchedCalendarIds: [String] = []

    func queueResponse(for calendarId: String, _ response: EventsResponse) {
        if self.responsesByCalendar[calendarId] == nil {
            self.responsesByCalendar[calendarId] = []
        }
        self.responsesByCalendar[calendarId]?.append(response)
    }

    func setError(for calendarId: String, _ error: Error) {
        self.errorsByCalendar[calendarId] = error
    }

    func fetchEvents(
        calendarId: String,
        from _: Date?,
        to _: Date?,
        syncToken _: String?
    ) async throws -> EventsResponse {
        self.fetchedCalendarIds.append(calendarId)

        if let error = self.errorsByCalendar[calendarId] {
            throw error
        }

        guard var responses = self.responsesByCalendar[calendarId], !responses.isEmpty else {
            return EventsResponse(events: [], nextSyncToken: nil)
        }

        let response = responses.removeFirst()
        self.responsesByCalendar[calendarId] = responses
        return response
    }

    func getFetchedCalendarIds() -> [String] { self.fetchedCalendarIds }
}

// MARK: - Multi-Calendar Test Sync Engine

/// Test-friendly SyncEngine that supports multi-calendar sync with TaskGroup.
private actor MultiCalendarTestSyncEngine {
    private let mockClient: MultiCalendarMockClient
    private let eventCache: EventCache
    private let appState: AppStateStore
    private let eventFilter: EventFilter
    private let healthTracker: CalendarHealthTracker?
    private var isSyncing = false

    init(
        mockClient: MultiCalendarMockClient,
        eventCache: EventCache,
        appState: AppStateStore,
        eventFilter: EventFilter,
        healthTracker: CalendarHealthTracker? = nil
    ) {
        self.mockClient = mockClient
        self.eventCache = eventCache
        self.appState = appState
        self.eventFilter = eventFilter
        self.healthTracker = healthTracker
    }

    func syncAllCalendars(_ calendarIds: [String]) async throws -> MultiCalendarSyncResult {
        guard !self.isSyncing else {
            throw CalendarError.syncInProgress
        }

        self.isSyncing = true
        defer { self.isSyncing = false }

        let enabledCalendars = await self.filterEnabledCalendars(calendarIds)
        guard !enabledCalendars.isEmpty else {
            return MultiCalendarSyncResult(
                events: [], filteredEvents: [], successfulCalendars: [:], failedCalendars: [:]
            )
        }

        return try await self.performMultiCalendarSync(enabledCalendars)
    }

    private func filterEnabledCalendars(_ calendarIds: [String]) async -> [String] {
        guard let healthTracker else { return calendarIds }
        var enabled: [String] = []
        for calendarId in calendarIds where await healthTracker.shouldPoll(calendarId) {
            enabled.append(calendarId)
        }
        return enabled
    }

    private func performMultiCalendarSync(_ calendarIds: [String]) async throws -> MultiCalendarSyncResult {
        typealias SyncOutcome = (String, Result<SyncResult, CalendarError>)

        let outcomes: [SyncOutcome] = try await withThrowingTaskGroup(of: SyncOutcome.self) { group in
            for calendarId in calendarIds {
                try Task.checkCancellation()
                group.addTask {
                    await self.syncSingleCalendar(calendarId)
                }
            }

            var results: [SyncOutcome] = []
            for try await outcome in group {
                results.append(outcome)
            }
            return results
        }

        return await self.buildMultiCalendarResult(from: outcomes)
    }

    private func syncSingleCalendar(_ calendarId: String) async -> (String, Result<SyncResult, CalendarError>) {
        do {
            let result = try await self.performSync(calendarId: calendarId)
            await self.healthTracker?.markSuccess(for: calendarId)
            return (calendarId, .success(result))
        } catch let error as CalendarError {
            await self.healthTracker?.markFailure(for: calendarId, error: error)
            return (calendarId, .failure(error))
        } catch {
            let calendarError = CalendarError.networkError(error.localizedDescription)
            await self.healthTracker?.markFailure(for: calendarId, error: calendarError)
            return (calendarId, .failure(calendarError))
        }
    }

    private func performSync(calendarId: String) async throws -> SyncResult {
        let syncToken = try await self.appState.getSyncToken(for: calendarId)
        let wasFullSync = syncToken == nil
        let now = Date()
        let endTime = Calendar.current.date(byAdding: .hour, value: 24, to: now) ?? now
        let response = try await self.mockClient.fetchEvents(
            calendarId: calendarId, from: now, to: endTime, syncToken: syncToken
        )
        return try await self.processResponse(response, calendarId: calendarId, wasFullSync: wasFullSync)
    }

    private func processResponse(
        _ response: EventsResponse,
        calendarId: String,
        wasFullSync: Bool
    ) async throws -> SyncResult {
        if let newToken = response.nextSyncToken {
            try await self.appState.setSyncToken(newToken, for: calendarId)
        }
        try await self.eventCache.save(response.events)
        let filteredEvents = response.events.filter { self.eventFilter.shouldAlert(for: $0) }
        return SyncResult(events: response.events, filteredEvents: filteredEvents, wasFullSync: wasFullSync)
    }

    private func buildMultiCalendarResult(
        from outcomes: [(String, Result<SyncResult, CalendarError>)]
    ) async -> MultiCalendarSyncResult {
        var allEvents: [CalendarEvent] = []
        var allFilteredEvents: [CalendarEvent] = []
        var successfulCalendars: [String: SyncResult] = [:]
        var failedCalendars: [String: CalendarError] = [:]

        for (calendarId, result) in outcomes {
            switch result {
            case let .success(syncResult):
                allEvents.append(contentsOf: syncResult.events)
                allFilteredEvents.append(contentsOf: syncResult.filteredEvents)
                successfulCalendars[calendarId] = syncResult
            case let .failure(error):
                failedCalendars[calendarId] = error
            }
        }

        return MultiCalendarSyncResult(
            events: allEvents,
            filteredEvents: allFilteredEvents,
            successfulCalendars: successfulCalendars,
            failedCalendars: failedCalendars
        )
    }

    func getMockFetchedCalendarIds() async -> [String] {
        await self.mockClient.getFetchedCalendarIds()
    }
}

// MARK: - Multi-Calendar Test Context

private struct MultiCalendarTestContext {
    let engine: MultiCalendarTestSyncEngine
    let mockClient: MultiCalendarMockClient
    let eventCache: EventCache
    let appState: AppStateStore
    let settings: SettingsStore
    let healthTracker: CalendarHealthTracker

    init(withHealthTracker: Bool = false) throws {
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
        let mockClient = MultiCalendarMockClient()
        let healthTracker = CalendarHealthTracker(
            disabledCalendarsPersistence: MockDisabledCalendarsPersistence()
        )

        self.settings = settings
        self.eventCache = eventCache
        self.appState = appState
        self.mockClient = mockClient
        self.healthTracker = healthTracker
        self.engine = MultiCalendarTestSyncEngine(
            mockClient: mockClient,
            eventCache: eventCache,
            appState: appState,
            eventFilter: eventFilter,
            healthTracker: withHealthTracker ? healthTracker : nil
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

// MARK: - Multi-Calendar Sync Tests

@Suite("SyncEngine Multi-Calendar Tests", .serialized)
struct SyncEngineMultiCalendarTests {
    @Test("sync multiple calendars merges results")
    func syncMultipleCalendarsMergesResults() async throws {
        let ctx = try MultiCalendarTestContext()

        let event1 = makeEvent(id: "event-1", calendarId: "cal-1", title: "Meeting 1")
        let event2 = makeEvent(id: "event-2", calendarId: "cal-2", title: "Meeting 2")

        await ctx.mockClient.queueResponse(for: "cal-1", EventsResponse(events: [event1], nextSyncToken: "t1"))
        await ctx.mockClient.queueResponse(for: "cal-2", EventsResponse(events: [event2], nextSyncToken: "t2"))

        let result = try await ctx.engine.syncAllCalendars(["cal-1", "cal-2"])

        #expect(result.events.count == 2)
        #expect(result.successfulCalendars.count == 2)
        #expect(result.failedCalendars.isEmpty)
        #expect(result.isFullSuccess)

        let eventIds: Set<String> = Set(result.events.map(\.id))
        #expect(eventIds.contains("event-1"))
        #expect(eventIds.contains("event-2"))
    }

    @Test("sync partial failure returns successful calendars")
    func syncPartialFailureReturnsSuccessfulCalendars() async throws {
        let ctx = try MultiCalendarTestContext()

        let event1 = makeEvent(id: "event-1", calendarId: "cal-1", title: "Meeting 1")
        await ctx.mockClient.queueResponse(for: "cal-1", EventsResponse(events: [event1], nextSyncToken: "t1"))
        await ctx.mockClient.setError(for: "cal-2", CalendarError.calendarNotFound(calendarId: "cal-2"))

        let result = try await ctx.engine.syncAllCalendars(["cal-1", "cal-2"])

        #expect(result.events.count == 1)
        #expect(result.events[0].id == "event-1")
        #expect(result.successfulCalendars.count == 1)
        #expect(result.successfulCalendars["cal-1"] != nil)
        #expect(result.failedCalendars.count == 1)
        #expect(result.failedCalendars["cal-2"] != nil)
        #expect(result.isPartialSuccess)
        #expect(!result.isFullSuccess)
    }

    @Test("sync with health tracker skips disabled calendars")
    func syncWithHealthTrackerSkipsDisabledCalendars() async throws {
        let ctx = try MultiCalendarTestContext(withHealthTracker: true)

        await ctx.healthTracker.disable("cal-disabled")

        let event1 = makeEvent(id: "event-1", calendarId: "cal-enabled", title: "Meeting 1")
        await ctx.mockClient.queueResponse(
            for: "cal-enabled", EventsResponse(events: [event1], nextSyncToken: "t1")
        )

        let result = try await ctx.engine.syncAllCalendars(["cal-enabled", "cal-disabled"])

        #expect(result.events.count == 1)
        #expect(result.successfulCalendars.count == 1)
        #expect(result.successfulCalendars["cal-enabled"] != nil)
        #expect(result.failedCalendars.isEmpty)

        let fetchedIds = await ctx.engine.getMockFetchedCalendarIds()
        #expect(!fetchedIds.contains("cal-disabled"))
        #expect(fetchedIds.contains("cal-enabled"))
    }

    @Test("sync with health tracker marks success on healthy calendar")
    func syncWithHealthTrackerMarksSuccessOnHealthyCalendar() async throws {
        let ctx = try MultiCalendarTestContext(withHealthTracker: true)

        let event1 = makeEvent(id: "event-1", calendarId: "cal-1", title: "Meeting 1")
        await ctx.mockClient.queueResponse(for: "cal-1", EventsResponse(events: [event1], nextSyncToken: "t1"))

        _ = try await ctx.engine.syncAllCalendars(["cal-1"])

        let health = await ctx.healthTracker.health(for: "cal-1")
        #expect(health == .healthy)
    }

    @Test("sync with health tracker marks failure on error")
    func syncWithHealthTrackerMarksFailureOnError() async throws {
        let ctx = try MultiCalendarTestContext(withHealthTracker: true)

        await ctx.mockClient.setError(for: "cal-fail", CalendarError.networkError("network down"))

        // Sync 3 times to trigger failing state (threshold is 3)
        for _ in 0 ..< 3 {
            _ = try await ctx.engine.syncAllCalendars(["cal-fail"])
        }

        let health = await ctx.healthTracker.health(for: "cal-fail")
        #expect(health == .failing)
    }

    @Test("sync empty calendar list returns empty result")
    func syncEmptyCalendarListReturnsEmptyResult() async throws {
        let ctx = try MultiCalendarTestContext()

        let result = try await ctx.engine.syncAllCalendars([])

        #expect(result.events.isEmpty)
        #expect(result.filteredEvents.isEmpty)
        #expect(result.successfulCalendars.isEmpty)
        #expect(result.failedCalendars.isEmpty)
    }

    @Test("sync stores sync tokens per calendar")
    func syncStoresSyncTokensPerCalendar() async throws {
        let ctx = try MultiCalendarTestContext()

        await ctx.mockClient.queueResponse(for: "cal-1", EventsResponse(events: [], nextSyncToken: "token-1"))
        await ctx.mockClient.queueResponse(for: "cal-2", EventsResponse(events: [], nextSyncToken: "token-2"))

        _ = try await ctx.engine.syncAllCalendars(["cal-1", "cal-2"])

        let token1 = try await ctx.appState.getSyncToken(for: "cal-1")
        let token2 = try await ctx.appState.getSyncToken(for: "cal-2")

        #expect(token1 == "token-1")
        #expect(token2 == "token-2")
    }
}
