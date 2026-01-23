import Foundation
import OSLog

// MARK: - CalendarHealth

/// Health state for a calendar's sync operations.
///
/// Health states determine polling behavior and UI indicators.
public enum CalendarHealth: String, Codable, Sendable, Equatable {
    /// Normal sync operations. Standard polling interval.
    case healthy

    /// Experiencing sync failures. 4x slower polling, yellow indicator.
    /// Automatically resets to healthy on next successful sync or app restart.
    case failing

    /// User explicitly disabled this calendar. No polling.
    /// This state is persisted across app restarts.
    case disabled
}

// MARK: - CalendarHealthDelegate

/// Delegate protocol for receiving health state change notifications.
public protocol CalendarHealthDelegate: AnyObject, Sendable {
    /// Called when a calendar's health state changes.
    func healthTracker(
        _ tracker: CalendarHealthTracker,
        didChangeHealthFor calendarId: String,
        from oldHealth: CalendarHealth,
        to newHealth: CalendarHealth
    ) async
}

// MARK: - CalendarHealthTracker

/// Tracks sync health per calendar for graceful degradation.
///
/// `CalendarHealthTracker` monitors sync success and failure patterns per calendar,
/// transitioning calendars to "failing" state after consecutive failures. This enables
/// the app to continue functioning when some calendars have issues (e.g., permissions
/// revoked, network issues for specific accounts).
///
/// ## Health State Transitions
/// - 3 consecutive failures → `failing`
/// - 1 success → `healthy` (resets failure count)
/// - App restart → `failing` calendars reset to `healthy`
/// - User action → `disabled` (persisted)
///
/// ## Polling Multiplier
/// - `healthy`: 1x (normal interval)
/// - `failing`: 4x (slower polling)
/// - `disabled`: ∞ (no polling)
///
/// ## Usage
/// ```swift
/// let tracker = CalendarHealthTracker()
/// await tracker.markSuccess(for: "primary")
/// await tracker.markFailure(for: "work", error: someError)
/// let multiplier = await tracker.pollingMultiplier(for: "primary")
/// ```
public actor CalendarHealthTracker {
    // MARK: - Constants

    /// Number of consecutive failures before transitioning to failing state.
    public static let failureThreshold = 3

    /// Polling multiplier for failing calendars.
    public static let failingPollingMultiplier: Double = 4.0

    // MARK: - Types

    /// Internal state for tracking calendar health.
    private struct CalendarState: Sendable {
        var health: CalendarHealth
        var consecutiveFailures: Int
        var lastError: String?
        var lastFailureDate: Date?

        init(health: CalendarHealth = .healthy) {
            self.health = health
            self.consecutiveFailures = 0
            self.lastError = nil
            self.lastFailureDate = nil
        }
    }

    // MARK: - Dependencies

    private let disabledCalendarsPersistence: DisabledCalendarsPersistence
    private let logger = Logger.sync

    // MARK: - State

    private var states: [String: CalendarState] = [:]
    private weak var delegate: CalendarHealthDelegate?

    // MARK: - Initialization

    /// Creates a CalendarHealthTracker with default persistence.
    public init() {
        self.disabledCalendarsPersistence = UserDefaultsDisabledCalendarsPersistence()
    }

    /// Creates a CalendarHealthTracker with custom persistence (for testing).
    public init(disabledCalendarsPersistence: DisabledCalendarsPersistence) {
        self.disabledCalendarsPersistence = disabledCalendarsPersistence
    }

    /// Sets the delegate for health change notifications.
    public func setDelegate(_ delegate: CalendarHealthDelegate?) {
        self.delegate = delegate
    }

    // MARK: - Health State Access

    /// Returns the current health state for a calendar.
    public func health(for calendarId: String) -> CalendarHealth {
        // Check persistent disabled state first
        if self.disabledCalendarsPersistence.isDisabled(calendarId) {
            return .disabled
        }
        return self.states[calendarId]?.health ?? .healthy
    }

    /// Returns the polling multiplier for a calendar based on its health.
    ///
    /// - Parameter calendarId: The calendar ID.
    /// - Returns: Multiplier to apply to base polling interval.
    ///   - `healthy`: 1.0
    ///   - `failing`: 4.0
    ///   - `disabled`: `Double.infinity` (no polling)
    public func pollingMultiplier(for calendarId: String) -> Double {
        switch self.health(for: calendarId) {
        case .healthy:
            1.0
        case .failing:
            Self.failingPollingMultiplier
        case .disabled:
            Double.infinity
        }
    }

    /// Returns whether a calendar should be polled.
    public func shouldPoll(_ calendarId: String) -> Bool {
        self.health(for: calendarId) != .disabled
    }

    /// Returns consecutive failure count for a calendar.
    public func consecutiveFailures(for calendarId: String) -> Int {
        self.states[calendarId]?.consecutiveFailures ?? 0
    }

    /// Returns the last error message for a calendar, if any.
    public func lastError(for calendarId: String) -> String? {
        self.states[calendarId]?.lastError
    }

    // MARK: - Health State Updates

    /// Records a successful sync for a calendar.
    ///
    /// Resets consecutive failures and transitions to healthy if needed.
    public func markSuccess(for calendarId: String) async {
        // Don't change disabled calendars
        guard !self.disabledCalendarsPersistence.isDisabled(calendarId) else {
            return
        }

        var state = self.states[calendarId] ?? CalendarState()
        let oldHealth = state.health

        state.consecutiveFailures = 0
        state.lastError = nil
        state.lastFailureDate = nil
        state.health = .healthy

        self.states[calendarId] = state

        if oldHealth != .healthy {
            self.logger.info("Calendar \(calendarId) recovered: \(oldHealth.rawValue) → healthy")
            await self.delegate?.healthTracker(self, didChangeHealthFor: calendarId, from: oldHealth, to: .healthy)
        }
    }

    /// Records a sync failure for a calendar.
    ///
    /// Increments consecutive failures and transitions to failing if threshold reached.
    public func markFailure(for calendarId: String, error: Error) async {
        // Don't change disabled calendars
        guard !self.disabledCalendarsPersistence.isDisabled(calendarId) else {
            return
        }

        var state = self.states[calendarId] ?? CalendarState()
        let oldHealth = state.health

        state.consecutiveFailures += 1
        state.lastError = error.localizedDescription
        state.lastFailureDate = Date()

        if state.consecutiveFailures >= Self.failureThreshold, state.health == .healthy {
            state.health = .failing
            self.logger.warning(
                "Calendar \(calendarId) marked failing after \(state.consecutiveFailures) consecutive failures"
            )
        }

        self.states[calendarId] = state

        if oldHealth != state.health {
            await self.delegate?.healthTracker(
                self,
                didChangeHealthFor: calendarId,
                from: oldHealth,
                to: state.health
            )
        }
    }

    // MARK: - User Actions

    /// Disables a calendar (user action). This state is persisted.
    public func disable(_ calendarId: String) async {
        let oldHealth = self.health(for: calendarId)
        guard oldHealth != .disabled else { return }

        self.disabledCalendarsPersistence.setDisabled(true, for: calendarId)

        // Clear in-memory state
        self.states.removeValue(forKey: calendarId)

        self.logger.info("Calendar \(calendarId) disabled by user")
        await self.delegate?.healthTracker(self, didChangeHealthFor: calendarId, from: oldHealth, to: .disabled)
    }

    /// Enables a calendar (user action). Removes from disabled list.
    public func enable(_ calendarId: String) async {
        guard self.disabledCalendarsPersistence.isDisabled(calendarId) else { return }

        self.disabledCalendarsPersistence.setDisabled(false, for: calendarId)

        self.logger.info("Calendar \(calendarId) enabled by user")
        await self.delegate?.healthTracker(self, didChangeHealthFor: calendarId, from: .disabled, to: .healthy)
    }

    /// Returns all currently disabled calendar IDs.
    public func disabledCalendarIds() -> Set<String> {
        self.disabledCalendarsPersistence.disabledCalendarIds()
    }

    // MARK: - Bulk Operations

    /// Resets all non-disabled calendars to healthy state.
    ///
    /// Called on app startup to clear transient failure states.
    public func resetTransientStates() {
        self.states.removeAll()
        self.logger.info("Reset all transient health states")
    }

    /// Returns health states for all known calendars (for UI display).
    public func allHealthStates() -> [String: CalendarHealth] {
        var result: [String: CalendarHealth] = [:]

        // Add in-memory states
        for (calendarId, state) in self.states {
            result[calendarId] = state.health
        }

        // Overlay disabled states
        for calendarId in self.disabledCalendarsPersistence.disabledCalendarIds() {
            result[calendarId] = .disabled
        }

        return result
    }
}

// MARK: - DisabledCalendarsPersistence Protocol

/// Protocol for persisting disabled calendar state.
public protocol DisabledCalendarsPersistence: Sendable {
    func isDisabled(_ calendarId: String) -> Bool
    func setDisabled(_ disabled: Bool, for calendarId: String)
    func disabledCalendarIds() -> Set<String>
}

// MARK: - UserDefaults Implementation

/// UserDefaults-based persistence for disabled calendars.
public final class UserDefaultsDisabledCalendarsPersistence: DisabledCalendarsPersistence, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "disabledCalendarIds"
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isDisabled(_ calendarId: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        let ids = self.defaults.stringArray(forKey: self.key) ?? []
        return ids.contains(calendarId)
    }

    public func setDisabled(_ disabled: Bool, for calendarId: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var ids = Set(self.defaults.stringArray(forKey: self.key) ?? [])
        if disabled {
            ids.insert(calendarId)
        } else {
            ids.remove(calendarId)
        }
        self.defaults.set(Array(ids), forKey: self.key)
    }

    public func disabledCalendarIds() -> Set<String> {
        self.lock.lock()
        defer { self.lock.unlock() }
        return Set(self.defaults.stringArray(forKey: self.key) ?? [])
    }
}

// MARK: - Mock Persistence for Testing

/// In-memory persistence for testing.
public final class MockDisabledCalendarsPersistence: DisabledCalendarsPersistence, @unchecked Sendable {
    private var disabled: Set<String> = []
    private let lock = NSLock()

    public init() {}

    public func isDisabled(_ calendarId: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.disabled.contains(calendarId)
    }

    public func setDisabled(_ disabled: Bool, for calendarId: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if disabled {
            self.disabled.insert(calendarId)
        } else {
            self.disabled.remove(calendarId)
        }
    }

    public func disabledCalendarIds() -> Set<String> {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.disabled
    }
}
