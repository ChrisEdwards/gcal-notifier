import Foundation
import Testing
@testable import GCalNotifierCore

@Suite("RateLimitManager Tests")
struct RateLimitManagerTests {
    // MARK: - Basic Backoff Tests

    @Test("Initially no calendars are in backoff")
    func initiallyNoBackoff() async {
        let manager = RateLimitManager()

        let shouldSkip = await manager.shouldSkip(calendarId: "primary")

        #expect(!shouldSkip)
    }

    @Test("After rate limit, calendar is in backoff")
    func rateLimitCreatesBackoff() async {
        let manager = RateLimitManager()

        await manager.handleRateLimit(calendarId: "primary", retryAfter: 60)

        let shouldSkip = await manager.shouldSkip(calendarId: "primary")
        #expect(shouldSkip)
    }

    @Test("Clearing backoff allows sync")
    func clearBackoffAllowsSync() async {
        let manager = RateLimitManager()
        await manager.handleRateLimit(calendarId: "primary", retryAfter: 60)

        await manager.clearBackoff(calendarId: "primary")

        let shouldSkip = await manager.shouldSkip(calendarId: "primary")
        #expect(!shouldSkip)
    }

    @Test("Clearing non-existent backoff is safe")
    func clearNonexistentBackoffIsSafe() async {
        let manager = RateLimitManager()

        // Should not throw or crash
        await manager.clearBackoff(calendarId: "nonexistent")

        let shouldSkip = await manager.shouldSkip(calendarId: "nonexistent")
        #expect(!shouldSkip)
    }

    // MARK: - Retry-After Tests

    @Test("Uses provided retry-after value")
    func usesProvidedRetryAfter() async {
        let manager = RateLimitManager()

        await manager.handleRateLimit(calendarId: "primary", retryAfter: 120)

        let remaining = await manager.remainingBackoff(calendarId: "primary")
        // Should be close to 120 seconds (allowing small timing variance)
        #expect(remaining > 115)
        #expect(remaining <= 120)
    }

    @Test("Calculates exponential backoff when no retry-after")
    func calculatesExponentialBackoff() async {
        let manager = RateLimitManager()

        // First rate limit with no retry-after
        await manager.handleRateLimit(calendarId: "primary", retryAfter: nil)

        let remaining = await manager.remainingBackoff(calendarId: "primary")
        // Base is 60s, with ±20% jitter, first attempt should be 48-72s
        #expect(remaining >= 48)
        #expect(remaining <= 72)
    }

    // MARK: - Consecutive Rate Limits Tests

    @Test("Tracks consecutive rate limits")
    func tracksConsecutiveRateLimits() async {
        let manager = RateLimitManager()

        await manager.handleRateLimit(calendarId: "primary", retryAfter: nil)
        #expect(await manager.consecutiveRateLimits(calendarId: "primary") == 1)

        await manager.handleRateLimit(calendarId: "primary", retryAfter: nil)
        #expect(await manager.consecutiveRateLimits(calendarId: "primary") == 2)

        await manager.handleRateLimit(calendarId: "primary", retryAfter: nil)
        #expect(await manager.consecutiveRateLimits(calendarId: "primary") == 3)
    }

    @Test("Clearing backoff resets consecutive count")
    func clearingResetsConsecutiveCount() async {
        let manager = RateLimitManager()
        await manager.handleRateLimit(calendarId: "primary", retryAfter: nil)
        await manager.handleRateLimit(calendarId: "primary", retryAfter: nil)

        await manager.clearBackoff(calendarId: "primary")

        #expect(await manager.consecutiveRateLimits(calendarId: "primary") == 0)
    }

    @Test("Exponential backoff increases with consecutive limits")
    func exponentialBackoffIncreases() async {
        let manager1 = RateLimitManager()
        let manager5 = RateLimitManager()

        // First rate limit
        await manager1.handleRateLimit(calendarId: "primary", retryAfter: nil)
        let backoff1 = await manager1.remainingBackoff(calendarId: "primary")

        // Simulate 5 consecutive rate limits
        for _ in 0 ..< 5 {
            await manager5.handleRateLimit(calendarId: "primary", retryAfter: nil)
        }
        let backoff5 = await manager5.remainingBackoff(calendarId: "primary")

        // 5th attempt should have significantly longer backoff (2^4 = 16x base)
        // With jitter, backoff5 should be much larger than backoff1
        #expect(backoff5 > backoff1 * 10)
    }

    // MARK: - Multiple Calendars Tests

    @Test("Handles multiple calendars independently")
    func handlesMultipleCalendarsIndependently() async {
        let manager = RateLimitManager()

        await manager.handleRateLimit(calendarId: "calendar1", retryAfter: 60)
        // calendar2 not rate limited

        #expect(await manager.shouldSkip(calendarId: "calendar1"))
        let shouldSkipCal2 = await manager.shouldSkip(calendarId: "calendar2")
        #expect(!shouldSkipCal2)
    }

    @Test("All backoffs returns only active backoffs")
    func allBackoffsReturnsOnlyActive() async {
        let manager = RateLimitManager()

        await manager.handleRateLimit(calendarId: "calendar1", retryAfter: 60)
        await manager.handleRateLimit(calendarId: "calendar2", retryAfter: 120)

        let allBackoffs = await manager.allBackoffs()

        #expect(allBackoffs.count == 2)
        guard let backoff1 = allBackoffs["calendar1"],
              let backoff2 = allBackoffs["calendar2"]
        else {
            Issue.record("Expected backoffs for both calendars")
            return
        }
        #expect(backoff1 < backoff2)
    }

    // MARK: - Clear All Tests

    @Test("Clear all removes all backoffs")
    func clearAllRemovesAllBackoffs() async {
        let manager = RateLimitManager()
        await manager.handleRateLimit(calendarId: "calendar1", retryAfter: 60)
        await manager.handleRateLimit(calendarId: "calendar2", retryAfter: 120)

        await manager.clearAll()

        let shouldSkipCal1 = await manager.shouldSkip(calendarId: "calendar1")
        let shouldSkipCal2 = await manager.shouldSkip(calendarId: "calendar2")
        let allBackoffs = await manager.allBackoffs()
        #expect(!shouldSkipCal1)
        #expect(!shouldSkipCal2)
        #expect(allBackoffs.isEmpty)
    }

    // MARK: - Remaining Backoff Tests

    @Test("Remaining backoff is zero for non-rate-limited calendar")
    func remainingBackoffZeroForNonRateLimited() async {
        let manager = RateLimitManager()

        let remaining = await manager.remainingBackoff(calendarId: "nonexistent")

        #expect(remaining == 0)
    }

    @Test("Remaining backoff decreases over time")
    func remainingBackoffDecreases() async throws {
        let manager = RateLimitManager()
        await manager.handleRateLimit(calendarId: "primary", retryAfter: 10)

        let initial = await manager.remainingBackoff(calendarId: "primary")

        // Wait a small amount
        try await Task.sleep(for: .milliseconds(100))

        let later = await manager.remainingBackoff(calendarId: "primary")

        #expect(later < initial)
    }

    // MARK: - Backoff Cap Tests

    @Test("Exponential backoff is capped at max attempts")
    func exponentialBackoffIsCapped() async {
        let manager = RateLimitManager()

        // Simulate many consecutive rate limits
        for _ in 0 ..< 20 {
            await manager.handleRateLimit(calendarId: "primary", retryAfter: nil)
        }

        let remaining = await manager.remainingBackoff(calendarId: "primary")

        // Max is 2^5 = 32x base (60s) = 1920s + jitter
        // With -20% to +20% jitter: 1536s to 2304s
        #expect(remaining <= 2500) // Some margin for timing
    }
}
