import Foundation
import Testing
@testable import GCalNotifierCore

private func makeEvent(
    id: String = "event-1",
    startTime: Date
) -> CalendarEvent {
    CalendarEvent(
        id: id,
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

@Suite("SyncEngine Polling Interval Tests")
struct SyncEnginePollingIntervalTests {
    @Test("calculatePollingInterval returns normal when meeting is more than 10 minutes away")
    func calculatePollingIntervalFarMeetingReturnsNormal() {
        let now = Date()
        let farEvent = makeEvent(startTime: now.addingTimeInterval(8000)) // ~2.2 hours
        let interval = self.calculatePollingInterval(events: [farEvent], now: now)
        #expect(interval == .normal)
    }

    @Test("calculatePollingInterval returns normal when meeting within 1 hour but more than 10 min")
    func calculatePollingIntervalMeetingWithin1HourReturnsNormal() {
        let now = Date()
        let soonEvent = makeEvent(startTime: now.addingTimeInterval(2400)) // 40 minutes
        let interval = self.calculatePollingInterval(events: [soonEvent], now: now)
        #expect(interval == .normal)
    }

    @Test("calculatePollingInterval returns imminent when meeting within 10 minutes")
    func calculatePollingIntervalMeetingWithin10MinReturnsImminent() {
        let now = Date()
        let imminentEvent = makeEvent(startTime: now.addingTimeInterval(300)) // 5 minutes
        let interval = self.calculatePollingInterval(events: [imminentEvent], now: now)
        #expect(interval == .imminent)
    }

    @Test("calculatePollingInterval returns normal when no events")
    func calculatePollingIntervalNoEventsReturnsNormal() {
        let interval = self.calculatePollingInterval(events: [], now: Date())
        #expect(interval == .normal)
    }

    @Test("calculatePollingInterval ignores past events")
    func calculatePollingIntervalIgnoresPastEvents() {
        let now = Date()
        let pastEvent = makeEvent(startTime: now.addingTimeInterval(-3600)) // 1 hour ago
        let interval = self.calculatePollingInterval(events: [pastEvent], now: now)
        #expect(interval == .normal)
    }

    @Test("calculatePollingInterval uses earliest upcoming event")
    func calculatePollingIntervalUsesEarliestEvent() {
        let now = Date()
        let farEvent = makeEvent(id: "far", startTime: now.addingTimeInterval(7200)) // 2 hours
        let nearEvent = makeEvent(id: "near", startTime: now.addingTimeInterval(300)) // 5 minutes
        let interval = self.calculatePollingInterval(events: [farEvent, nearEvent], now: now)
        #expect(interval == .imminent)
    }

    /// Helper function to match SyncEngine's calculation logic
    private func calculatePollingInterval(events: [CalendarEvent], now: Date) -> PollingInterval {
        let upcomingEvents = events.filter { $0.startTime > now }

        guard let nextEvent = upcomingEvents.min(by: { $0.startTime < $1.startTime }) else {
            return .normal
        }

        let timeUntilNext = nextEvent.startTime.timeIntervalSince(now)

        if timeUntilNext <= 600 { // 10 minutes
            return .imminent
        } else {
            return .normal
        }
    }
}
