import Foundation
import OSLog

// MARK: - Polling Intervals

/// Polling intervals for adaptive sync scheduling.
public enum PollingInterval: TimeInterval, Sendable {
    /// Default interval when no meetings are within 2 hours.
    case idle = 900 // 15 minutes

    /// Interval when a meeting is within 1 hour.
    case upcoming = 300 // 5 minutes

    /// Interval when a meeting is within 10 minutes.
    case imminent = 60 // 1 minute
}

// MARK: - SyncResult

/// Result of a sync operation.
public struct SyncResult: Sendable, Equatable {
    public let events: [CalendarEvent]
    public let filteredEvents: [CalendarEvent]
    public let wasFullSync: Bool

    public init(events: [CalendarEvent], filteredEvents: [CalendarEvent], wasFullSync: Bool) {
        self.events = events
        self.filteredEvents = filteredEvents
        self.wasFullSync = wasFullSync
    }
}

// MARK: - MultiCalendarSyncResult

/// Result of syncing multiple calendars concurrently.
public struct MultiCalendarSyncResult: Sendable {
    /// Merged events from all successful calendar syncs.
    public let events: [CalendarEvent]
    /// Merged filtered events from all successful calendar syncs.
    public let filteredEvents: [CalendarEvent]
    /// Per-calendar sync results for successful syncs.
    public let successfulCalendars: [String: SyncResult]
    /// Per-calendar errors for failed syncs.
    public let failedCalendars: [String: CalendarError]

    public init(
        events: [CalendarEvent],
        filteredEvents: [CalendarEvent],
        successfulCalendars: [String: SyncResult],
        failedCalendars: [String: CalendarError]
    ) {
        self.events = events
        self.filteredEvents = filteredEvents
        self.successfulCalendars = successfulCalendars
        self.failedCalendars = failedCalendars
    }

    /// Whether all calendars synced successfully.
    public var isFullSuccess: Bool { self.failedCalendars.isEmpty }

    /// Whether at least one calendar synced successfully.
    public var isPartialSuccess: Bool { !self.successfulCalendars.isEmpty }
}

// MARK: - SyncEngineDelegate

/// Delegate protocol for receiving sync updates.
public protocol SyncEngineDelegate: AnyObject, Sendable {
    /// Called when sync completes with updated events.
    func syncEngine(_ engine: SyncEngine, didSyncEvents result: SyncResult) async
    /// Called when sync fails with an error.
    func syncEngine(_ engine: SyncEngine, didFailWithError error: CalendarError) async
}

// MARK: - SyncEngine

/// Orchestrates calendar synchronization with adaptive polling.
///
/// `SyncEngine` coordinates fetching events from Google Calendar, caching them locally,
/// and applying user-configured filters. It handles sync token management, including
/// recovering from 410 (token invalid) errors by clearing the token and performing a full sync.
///
/// ## Usage
/// ```swift
/// let engine = SyncEngine(
///     calendarClient: googleClient,
///     eventCache: cache,
///     appState: stateStore,
///     eventFilter: filter
/// )
/// let result = try await engine.sync(calendarId: "primary")
/// let nextPoll = engine.calculatePollingInterval(events: result.filteredEvents)
/// ```
public actor SyncEngine {
    // MARK: - Dependencies

    private let calendarClient: GoogleCalendarClient
    private let eventCache: EventCache
    private let appState: AppStateStore
    private let eventFilter: EventFilter
    private let healthTracker: CalendarHealthTracker?
    private let logger = Logger.sync

    // MARK: - State

    private weak var delegate: SyncEngineDelegate?
    private var isSyncing = false

    // MARK: - Configuration

    /// Default time window for full sync (24 hours).
    private let syncWindowHours: Int = 24

    // MARK: - Initialization

    /// Creates a SyncEngine with required dependencies.
    /// - Parameters:
    ///   - calendarClient: Client for Google Calendar API calls.
    ///   - eventCache: Local storage for events.
    ///   - appState: Storage for sync tokens and app state.
    ///   - eventFilter: Filter for determining which events to alert on.
    ///   - healthTracker: Optional tracker for per-calendar health monitoring.
    public init(
        calendarClient: GoogleCalendarClient,
        eventCache: EventCache,
        appState: AppStateStore,
        eventFilter: EventFilter,
        healthTracker: CalendarHealthTracker? = nil
    ) {
        self.calendarClient = calendarClient
        self.eventCache = eventCache
        self.appState = appState
        self.eventFilter = eventFilter
        self.healthTracker = healthTracker
    }

    /// Sets the delegate for receiving sync updates.
    public func setDelegate(_ delegate: SyncEngineDelegate?) {
        self.delegate = delegate
    }

    // MARK: - Sync Operations

    /// Performs a sync for the specified calendar.
    ///
    /// Uses incremental sync with sync token if available, otherwise performs full sync.
    /// On 410 error (token invalid), clears the token and retries with full sync.
    ///
    /// - Parameter calendarId: The calendar ID to sync.
    /// - Returns: Result containing all events and filtered events.
    /// - Throws: `CalendarError` if sync fails after retry.
    public func sync(calendarId: String) async throws -> SyncResult {
        guard !self.isSyncing else {
            throw CalendarError.syncInProgress
        }

        self.isSyncing = true
        defer { self.isSyncing = false }

        do {
            let result = try await self.performSync(calendarId: calendarId)
            await self.delegate?.syncEngine(self, didSyncEvents: result)
            return result
        } catch let error as CalendarError {
            await self.delegate?.syncEngine(self, didFailWithError: error)
            throw error
        } catch {
            let calendarError = CalendarError.networkError(error.localizedDescription)
            await self.delegate?.syncEngine(self, didFailWithError: calendarError)
            throw calendarError
        }
    }

    // MARK: - Multi-Calendar Sync

    /// Syncs multiple calendars concurrently using TaskGroup.
    ///
    /// Requests are made in parallel, and results are merged. Partial failures are handled
    /// gracefully - successful calendars return their events while failed calendars are
    /// tracked separately. Health tracker is updated for each calendar if configured.
    ///
    /// - Parameter calendarIds: List of calendar IDs to sync.
    /// - Returns: Aggregated result with merged events and per-calendar status.
    /// - Throws: `CancellationError` if the task is cancelled. Individual calendar
    ///           failures are captured in the result, not thrown.
    public func syncAllCalendars(_ calendarIds: [String]) async throws -> MultiCalendarSyncResult {
        guard !self.isSyncing else {
            throw CalendarError.syncInProgress
        }

        self.isSyncing = true
        defer { self.isSyncing = false }

        // Filter out disabled calendars if health tracker is available
        let enabledCalendars = await self.filterEnabledCalendars(calendarIds)

        guard !enabledCalendars.isEmpty else {
            return MultiCalendarSyncResult(
                events: [],
                filteredEvents: [],
                successfulCalendars: [:],
                failedCalendars: [:]
            )
        }

        return try await self.performMultiCalendarSync(enabledCalendars)
    }

    // MARK: - Polling Interval

    /// Calculates the appropriate polling interval based on upcoming events.
    ///
    /// - Parameter events: List of events to consider.
    /// - Parameter now: Current time (defaults to now).
    /// - Returns: The recommended polling interval.
    public func calculatePollingInterval(events: [CalendarEvent], now: Date = Date()) -> PollingInterval {
        let upcomingEvents = events.filter { $0.startTime > now }

        guard let nextEvent = upcomingEvents.min(by: { $0.startTime < $1.startTime }) else {
            return .idle
        }

        let timeUntilNext = nextEvent.startTime.timeIntervalSince(now)

        if timeUntilNext <= 600 { // 10 minutes
            return .imminent
        } else if timeUntilNext <= 3600 { // 1 hour
            return .upcoming
        } else {
            return .idle
        }
    }

    // MARK: - Private Methods

    private func performSync(calendarId: String) async throws -> SyncResult {
        let syncToken = try await self.appState.getSyncToken(for: calendarId)
        let wasFullSync = syncToken == nil

        do {
            let response = try await self.fetchEvents(calendarId: calendarId, syncToken: syncToken)
            return try await self.processResponse(response, calendarId: calendarId, wasFullSync: wasFullSync)
        } catch CalendarError.syncTokenInvalid {
            self.logger.info("Sync token invalid for calendar \(calendarId), performing full sync")
            try await self.appState.clearSyncToken(for: calendarId)
            let response = try await self.fetchEvents(calendarId: calendarId, syncToken: nil)
            return try await self.processResponse(response, calendarId: calendarId, wasFullSync: true)
        }
    }

    private func fetchEvents(calendarId: String, syncToken: String?) async throws -> EventsResponse {
        if let syncToken {
            self.logger.debug("Performing incremental sync for calendar \(calendarId)")
            return try await self.calendarClient.fetchEvents(calendarId: calendarId, syncToken: syncToken)
        } else {
            self.logger.debug("Performing full sync for calendar \(calendarId)")
            let now = Date()
            let endTime = Calendar.current.date(byAdding: .hour, value: self.syncWindowHours, to: now) ?? now
            return try await self.calendarClient.fetchEvents(calendarId: calendarId, from: now, to: endTime)
        }
    }

    private func processResponse(
        _ response: EventsResponse,
        calendarId: String,
        wasFullSync: Bool
    ) async throws -> SyncResult {
        // Store new sync token if provided
        if let newToken = response.nextSyncToken {
            try await self.appState.setSyncToken(newToken, for: calendarId)
        }

        // Save events to cache
        try await self.eventCache.save(response.events)

        // Apply filter to determine which events should alert
        let filteredEvents = response.events.filter { self.eventFilter.shouldAlert(for: $0) }

        self.logger.info(
            "Sync complete: \(response.events.count) events, \(filteredEvents.count) alertable"
        )

        return SyncResult(events: response.events, filteredEvents: filteredEvents, wasFullSync: wasFullSync)
    }

    // MARK: - Multi-Calendar Sync Helpers

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

        self.logger.info(
            "Multi-sync complete: \(successfulCalendars.count) ok, \(failedCalendars.count) failed"
        )

        return MultiCalendarSyncResult(
            events: allEvents,
            filteredEvents: allFilteredEvents,
            successfulCalendars: successfulCalendars,
            failedCalendars: failedCalendars
        )
    }
}
