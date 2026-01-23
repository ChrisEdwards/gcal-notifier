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
    public init(
        calendarClient: GoogleCalendarClient,
        eventCache: EventCache,
        appState: AppStateStore,
        eventFilter: EventFilter
    ) {
        self.calendarClient = calendarClient
        self.eventCache = eventCache
        self.appState = appState
        self.eventFilter = eventFilter
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
}
