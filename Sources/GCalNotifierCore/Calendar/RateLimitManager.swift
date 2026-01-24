import Foundation
import OSLog

/// Manages rate limit backoff per calendar with exponential delay and jitter.
///
/// `RateLimitManager` tracks rate limit responses (HTTP 429/403) per calendar and
/// calculates appropriate backoff durations using exponential backoff with jitter.
/// This prevents thundering herd problems when multiple calendars are rate limited.
///
/// ## Usage
/// ```swift
/// let manager = RateLimitManager()
/// manager.handleRateLimit(calendarId: "primary", retryAfter: 60)
/// if manager.shouldSkip(calendarId: "primary") {
///     // Skip this calendar, it's in backoff
/// }
/// manager.clearBackoff(calendarId: "primary") // After successful sync
/// ```
public actor RateLimitManager {
    // MARK: - Constants

    /// Default base backoff duration in seconds (1 minute).
    public static let baseBackoffSeconds: TimeInterval = 60

    /// Maximum number of attempts for exponential growth (caps at 2^5 = 32x base).
    public static let maxBackoffAttempts = 5

    /// Jitter range as percentage (±20%).
    public static let jitterRange: ClosedRange<Double> = -0.2 ... 0.2

    // MARK: - Types

    /// Internal state for tracking backoff per calendar.
    private struct BackoffState: Sendable {
        var backoffUntil: Date
        var consecutiveRateLimits: Int
        var retryAfterProvided: TimeInterval?
    }

    // MARK: - Dependencies

    private let logger = Logger.sync

    // MARK: - State

    private var states: [String: BackoffState] = [:]

    // MARK: - Initialization

    public init() {}

    // MARK: - Rate Limit Handling

    /// Records a rate limit response for a calendar.
    ///
    /// - Parameters:
    ///   - calendarId: The calendar that was rate limited.
    ///   - retryAfter: Optional Retry-After header value from the API response.
    public func handleRateLimit(calendarId: String, retryAfter: TimeInterval?) {
        var state = self.states[calendarId] ?? BackoffState(
            backoffUntil: Date.distantPast,
            consecutiveRateLimits: 0,
            retryAfterProvided: nil
        )

        state.consecutiveRateLimits += 1
        state.retryAfterProvided = retryAfter

        let backoffDuration = retryAfter ?? self.calculateExponentialBackoff(
            attempts: state.consecutiveRateLimits
        )
        state.backoffUntil = Date().addingTimeInterval(backoffDuration)

        self.states[calendarId] = state

        let attempts = state.consecutiveRateLimits
        let backoffSecs = Int(backoffDuration)
        self.logger.warning("Calendar \(calendarId) rate limited, backoff \(backoffSecs)s (attempt \(attempts))")
    }

    /// Checks if a calendar should be skipped due to active backoff.
    ///
    /// - Parameter calendarId: The calendar ID to check.
    /// - Returns: `true` if the calendar is in backoff and should be skipped.
    public func shouldSkip(calendarId: String) -> Bool {
        guard let state = self.states[calendarId] else { return false }
        return Date() < state.backoffUntil
    }

    /// Returns the remaining backoff time for a calendar.
    ///
    /// - Parameter calendarId: The calendar ID to check.
    /// - Returns: Remaining seconds until backoff expires, or 0 if not in backoff.
    public func remainingBackoff(calendarId: String) -> TimeInterval {
        guard let state = self.states[calendarId] else { return 0 }
        let remaining = state.backoffUntil.timeIntervalSinceNow
        return max(0, remaining)
    }

    /// Clears backoff state for a calendar after a successful sync.
    ///
    /// - Parameter calendarId: The calendar ID to clear.
    public func clearBackoff(calendarId: String) {
        if self.states.removeValue(forKey: calendarId) != nil {
            self.logger.info("Cleared rate limit backoff for calendar \(calendarId)")
        }
    }

    /// Returns the number of consecutive rate limits for a calendar.
    ///
    /// - Parameter calendarId: The calendar ID to check.
    /// - Returns: The consecutive rate limit count, or 0 if none.
    public func consecutiveRateLimits(calendarId: String) -> Int {
        self.states[calendarId]?.consecutiveRateLimits ?? 0
    }

    /// Returns backoff information for all calendars currently in backoff.
    ///
    /// - Returns: Dictionary mapping calendar IDs to their remaining backoff seconds.
    public func allBackoffs() -> [String: TimeInterval] {
        let now = Date()
        var result: [String: TimeInterval] = [:]
        for (calendarId, state) in self.states {
            let remaining = state.backoffUntil.timeIntervalSince(now)
            if remaining > 0 {
                result[calendarId] = remaining
            }
        }
        return result
    }

    /// Clears all backoff states. Typically called on app restart.
    public func clearAll() {
        self.states.removeAll()
        self.logger.info("Cleared all rate limit backoffs")
    }

    // MARK: - Private Methods

    private func calculateExponentialBackoff(attempts: Int) -> TimeInterval {
        let cappedAttempts = min(attempts, Self.maxBackoffAttempts)
        let base = Self.baseBackoffSeconds
        let exponential = base * pow(2.0, Double(cappedAttempts - 1))

        // Add jitter (±20%) to prevent thundering herd
        let jitter = exponential * Double.random(in: Self.jitterRange)
        return exponential + jitter
    }
}
