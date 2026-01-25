import Foundation

// MARK: - Polling Intervals

/// Polling intervals for adaptive sync scheduling.
public enum PollingInterval: TimeInterval, Sendable {
    /// Default interval (5 minutes).
    case normal = 300

    /// Interval when a meeting is within 10 minutes (1 minute).
    case imminent = 60
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
