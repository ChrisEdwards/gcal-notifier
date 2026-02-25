import Foundation
import Testing
@testable import GCalNotifier
@testable import GCalNotifierCore

// MARK: - Test Helpers

/// Creates a "now" time at 10 AM today to avoid late-night test failures.
private func testNow() -> Date {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    return calendar.date(byAdding: .hour, value: 10, to: today) ?? today
}

private func makeTestEvent(
    startTime: Date,
    endTime: Date? = nil
) -> CalendarEvent {
    let resolvedEnd = endTime ?? startTime.addingTimeInterval(3600)
    return CalendarEvent(
        id: "countdown-test",
        calendarId: "primary",
        title: "Countdown Test",
        startTime: startTime,
        endTime: resolvedEnd,
        isAllDay: false,
        location: nil,
        meetingLinks: [],
        isOrganizer: false,
        attendeeCount: 1,
        responseStatus: .accepted
    )
}

// MARK: - Countdown Formatting Tests

@Suite("Menu Countdown Formatting Tests")
struct MenuCountdownFormattingTests {
    @Test("Formats countdown correctly")
    func formatsCountdownCorrectly() {
        let now = testNow()
        let event = makeTestEvent(startTime: now.addingTimeInterval(32 * 60))
        let countdown = MenuBuilder.formatCountdown(to: event, now: now)
        #expect(countdown == "32m")
    }

    @Test("Formats countdown with hours")
    func formatsCountdownWithHours() {
        let now = testNow()
        let event = makeTestEvent(startTime: now.addingTimeInterval(90 * 60))
        let countdown = MenuBuilder.formatCountdown(to: event, now: now)
        #expect(countdown == "1h 30m")
    }

    @Test("Shows 'now' for past events")
    func showsNowForPastEvents() {
        let now = testNow()
        let event = makeTestEvent(startTime: now.addingTimeInterval(-5 * 60))
        let countdown = MenuBuilder.formatCountdown(to: event, now: now)
        #expect(countdown == "now")
    }
}
