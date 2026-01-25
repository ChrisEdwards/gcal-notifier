import Foundation
import OSLog

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
    private let rateLimitManager: RateLimitManager?
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
    ///   - rateLimitManager: Optional manager for rate limit backoff tracking.
    public init(
        calendarClient: GoogleCalendarClient,
        eventCache: EventCache,
        appState: AppStateStore,
        eventFilter: EventFilter,
        healthTracker: CalendarHealthTracker? = nil,
        rateLimitManager: RateLimitManager? = nil
    ) {
        self.calendarClient = calendarClient
        self.eventCache = eventCache
        self.appState = appState
        self.eventFilter = eventFilter
        self.healthTracker = healthTracker
        self.rateLimitManager = rateLimitManager
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

    // MARK: - Back-to-Back Detection

    /// Detects the current back-to-back meeting state.
    ///
    /// - Parameter now: Current time (defaults to now).
    /// - Returns: The detected back-to-back state, or `.none` if not in a back-to-back situation.
    public func detectBackToBackState(now: Date = Date()) async -> BackToBackState {
        do {
            let events = try await eventCache.load()
            return BackToBackState.detect(from: events, now: now)
        } catch {
            self.logger.error("Failed to load events for back-to-back detection: \(error.localizedDescription)")
            return .none
        }
    }

    /// Finds the current meeting the user is in (if any).
    ///
    /// - Parameter now: Current time (defaults to now).
    /// - Returns: The current meeting event, or `nil` if not in a meeting.
    public func currentMeeting(now: Date = Date()) async -> CalendarEvent? {
        do {
            let events = try await eventCache.load()
            return events.first { event in
                event.isInProgress(at: now) && event.hasVideoLink
            }
        } catch {
            return nil
        }
    }

    /// Finds the next meeting that is back-to-back with the current meeting.
    ///
    /// - Parameter now: Current time (defaults to now).
    /// - Returns: The next back-to-back meeting, or `nil` if none.
    public func nextBackToBackMeeting(now: Date = Date()) async -> CalendarEvent? {
        await self.detectBackToBackState(now: now).nextBackToBackMeeting
    }

    /// Checks whether the user is currently in a meeting.
    ///
    /// - Parameter now: Current time (defaults to now).
    /// - Returns: `true` if the user is in a meeting with a video link.
    public func isUserInMeeting(now: Date = Date()) async -> Bool {
        await self.currentMeeting(now: now) != nil
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

        // Merge events into cache (preserve other calendars, handle deletions).
        try await self.eventCache.merge(
            events: response.events,
            deletedEventIds: response.deletedEventIds,
            for: calendarId,
            isFullSync: wasFullSync
        )

        let mergedEvents = try await self.eventCache.events(forCalendar: calendarId)
        let filteredEvents = mergedEvents.filter { self.eventFilter.shouldAlert(for: $0) }

        self.logger.info(
            "Sync complete: \(mergedEvents.count) events, \(filteredEvents.count) alertable"
        )

        return SyncResult(events: mergedEvents, filteredEvents: filteredEvents, wasFullSync: wasFullSync)
    }

    // MARK: - Multi-Calendar Sync Helpers

    private func filterEnabledCalendars(_ calendarIds: [String]) async -> [String] {
        var enabled: [String] = []
        for calendarId in calendarIds {
            // Skip disabled calendars (health tracker)
            if let healthTracker {
                let shouldPoll = await healthTracker.shouldPoll(calendarId)
                if !shouldPoll {
                    continue
                }
            }
            // Skip rate-limited calendars
            if let rateLimitManager {
                let shouldSkip = await rateLimitManager.shouldSkip(calendarId: calendarId)
                if shouldSkip {
                    let remaining = await rateLimitManager.remainingBackoff(calendarId: calendarId)
                    self.logger.info("Skipping rate-limited calendar \(calendarId), \(Int(remaining))s remaining")
                    continue
                }
            }
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
            await self.rateLimitManager?.clearBackoff(calendarId: calendarId)
            return (calendarId, .success(result))
        } catch let error as CalendarError {
            await self.healthTracker?.markFailure(for: calendarId, error: error)
            await self.handleRateLimitIfNeeded(calendarId: calendarId, error: error)
            return (calendarId, .failure(error))
        } catch {
            let calendarError = CalendarError.networkError(error.localizedDescription)
            await self.healthTracker?.markFailure(for: calendarId, error: calendarError)
            return (calendarId, .failure(calendarError))
        }
    }

    private func handleRateLimitIfNeeded(calendarId: String, error: CalendarError) async {
        guard let rateLimitManager else { return }
        if case let .rateLimited(retryAfter) = error {
            let retrySeconds = retryAfter.map { TimeInterval($0) }
            await rateLimitManager.handleRateLimit(calendarId: calendarId, retryAfter: retrySeconds)
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
