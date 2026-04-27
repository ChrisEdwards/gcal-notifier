import Foundation
import Testing
@testable import GCalNotifierCore

@Suite("NotificationScheduler Durable Notification Tests")
struct NotificationSchedulerDurableTests {
    @Test("Durable Stage 2 notification uses alert snapshot content")
    func durableStage2NotificationUsesAlertSnapshotContent() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let fireDate = Date(timeIntervalSince1970: 1_800_000_000)
        let alert = try makeStage2NotificationTestAlert(fireDate: fireDate)

        await scheduler.scheduleNotification(for: alert)

        let request = try #require(mockCenter.pendingRequests.first)
        #expect(request.identifier == alert.id)
        #expect(request.title == alert.notificationPayload.title)
        #expect(request.body == alert.notificationPayload.body)
        #expect(request.body.contains(alert.eventTitle))
        #expect(request.categoryIdentifier == AlertNotificationPayload.stage2CategoryIdentifier)
        #expect(request.soundIsNil == false)
        #expect(request.isTimeSensitive)
    }

    @Test("Durable Stage 2 notification includes cache-independent fallback metadata")
    func durableStage2NotificationIncludesFallbackMetadata() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let fireDate = Date(timeIntervalSince1970: 1_800_000_000)
        let alert = try makeStage2NotificationTestAlert(fireDate: fireDate)

        await scheduler.scheduleNotification(for: alert)

        let request = try #require(mockCenter.pendingRequests.first)
        #expect(request.userInfo["alertId"] == alert.id)
        #expect(request.userInfo["eventId"] == alert.eventId)
        #expect(request.userInfo["stage"] == AlertStage.stage2.rawValue)
        #expect(request.userInfo["eventTitle"] == alert.eventTitle)
        #expect(request.userInfo["joinURL"] == alert.joinURL?.absoluteString)
        #expect(request.userInfo["calendarURL"] == alert.calendarURL?.absoluteString)
        #expect(request.userInfo["notificationBody"] == alert.notificationPayload.body)
        #expect(request.userInfo["notificationUrgency"] == AlertNotificationUrgency.timeSensitive.rawValue)
    }

    @Test("Durable Stage 2 notification creates calendar trigger with correct date")
    func durableStage2NotificationCreatesCalendarTriggerWithCorrectDate() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let calendar = Calendar.current
        let fireDate = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 20, hour: 9, minute: 45, second: 30)
        ))
        let alert = try makeStage2NotificationTestAlert(fireDate: fireDate)

        await scheduler.scheduleNotification(for: alert)

        let request = try #require(mockCenter.pendingRequests.first)
        #expect(request.triggerYear == 2026)
        #expect(request.triggerMonth == 7)
        #expect(request.triggerDay == 20)
        #expect(request.triggerHour == 9)
        #expect(request.triggerMinute == 45)
        #expect(request.triggerSecond == 30)
        #expect(request.triggerRepeats == false)
    }
}

private func makeStage2NotificationTestAlert(fireDate: Date) throws -> ScheduledAlert {
    let eventStart = fireDate.addingTimeInterval(120)
    let eventEnd = eventStart.addingTimeInterval(1800)
    let joinURL = try #require(URL(string: "https://meet.google.com/stage-two"))
    let calendarURL = try #require(URL(string: "https://calendar.google.com/event?eid=stage-two"))

    return ScheduledAlert(
        id: "calendar-1::event-1-stage2",
        eventId: "calendar-1::event-1",
        stage: .stage2,
        scheduledFireTime: fireDate,
        eventTitle: "Cache Independent Review",
        eventStartTime: eventStart,
        eventEndTime: eventEnd,
        joinURL: joinURL,
        calendarURL: calendarURL,
        notificationPayload: AlertNotificationPayload.make(
            eventTitle: "Cache Independent Review",
            eventStartTime: eventStart,
            stage: .stage2
        )
    )
}
