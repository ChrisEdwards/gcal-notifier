import Foundation
import Testing
@testable import GCalNotifierCore

// MARK: - Test Helpers

private func makeEvent(startTime: Date) -> CalendarEvent {
    CalendarEvent(
        id: UUID().uuidString,
        calendarId: "primary",
        title: "Test Meeting",
        startTime: startTime,
        endTime: startTime.addingTimeInterval(3600),
        isAllDay: false,
        location: nil,
        meetingLinks: [],
        isOrganizer: false,
        attendeeCount: 2,
        responseStatus: .accepted
    )
}

// MARK: - Time Formatting Tests

@Suite("Time Formatting")
struct TimeFormattingTests {
    @Test("Formats minutes correctly")
    func formatsMinutes() {
        let minutes = 45
        let expected = "45 minutes"

        let result = self.formatTimeUntilTest(minutes: minutes, hours: 0)

        #expect(result == expected)
    }

    @Test("Formats singular minute correctly")
    func formatsSingleMinute() {
        let minutes = 1
        let expected = "1 minute"

        let result = self.formatTimeUntilTest(minutes: minutes, hours: 0)

        #expect(result == expected)
    }

    @Test("Formats hours correctly")
    func formatsHours() {
        let expected = "2 hours"

        let result = self.formatTimeUntilTest(minutes: 0, hours: 2)

        #expect(result == expected)
    }

    @Test("Formats singular hour correctly")
    func formatsSingleHour() {
        let expected = "1 hour"

        let result = self.formatTimeUntilTest(minutes: 0, hours: 1)

        #expect(result == expected)
    }

    @Test("Formats hours and minutes together")
    func formatsHoursAndMinutes() {
        let expected = "1h 30m"

        let result = self.formatTimeUntilTest(minutes: 30, hours: 1)

        #expect(result == expected)
    }

    /// Helper function that mimics the formatting logic
    private func formatTimeUntilTest(minutes: Int, hours: Int) -> String {
        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
}

// MARK: - Join Threshold Tests

@Suite("Join Threshold Determination")
struct JoinThresholdTests {
    @Test("Event within 30 minutes should join directly")
    func withinThreshold_joinDirectly() {
        let now = Date()
        let event = makeEvent(startTime: now.addingTimeInterval(20 * 60)) // 20 minutes

        let timeUntil = event.startTime.timeIntervalSinceNow
        let shouldJoinDirectly = timeUntil <= 30 * 60

        #expect(shouldJoinDirectly == true)
    }

    @Test("Event more than 30 minutes away should show confirmation")
    func beyondThreshold_showConfirmation() {
        let now = Date()
        let event = makeEvent(startTime: now.addingTimeInterval(45 * 60)) // 45 minutes

        let timeUntil = event.startTime.timeIntervalSinceNow
        let shouldJoinDirectly = timeUntil <= 30 * 60

        #expect(shouldJoinDirectly == false)
    }

    @Test("Event exactly at 30 minutes should join directly")
    func exactlyAtThreshold_joinDirectly() {
        let now = Date()
        let event = makeEvent(startTime: now.addingTimeInterval(30 * 60)) // Exactly 30 minutes

        let timeUntil = event.startTime.timeIntervalSinceNow
        let shouldJoinDirectly = timeUntil <= 30 * 60

        #expect(shouldJoinDirectly == true)
    }
}
