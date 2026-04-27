import Foundation
import Testing
@testable import GCalNotifierCore

@Suite("NotificationScheduler Durable Notification Tests")
struct NotificationSchedulerDurableTests {
    @Test("Durable Stage 1 notification uses gentle snapshot content")
    func durableStage1NotificationUsesGentleSnapshotContent() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let fireDate = Date(timeIntervalSince1970: 1_800_000_000)
        let alert = try makeStage1NotificationTestAlert(fireDate: fireDate)

        await scheduler.scheduleNotification(for: alert)

        let request = try #require(mockCenter.pendingRequests.first)
        #expect(request.identifier == alert.id)
        #expect(request.title == alert.notificationPayload.title)
        #expect(request.body.contains(alert.eventTitle))
        #expect(request.categoryIdentifier == NotificationScheduler.stage1Snooze5Category)
        #expect(request.soundIsNil)
        #expect(!request.isTimeSensitive)
        #expect(request.userInfo["notificationUrgency"] == AlertNotificationUrgency.active.rawValue)
    }

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

    @Test("Stage 1 notification urgency is lower than Stage 2")
    func stage1NotificationUrgencyIsLowerThanStage2() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)

        let fireDate = Date(timeIntervalSince1970: 1_800_000_000)
        let stage1 = try makeStage1NotificationTestAlert(fireDate: fireDate)
        let stage2 = try makeStage2NotificationTestAlert(fireDate: fireDate.addingTimeInterval(60))

        await scheduler.scheduleNotification(for: stage1)
        await scheduler.scheduleNotification(for: stage2)

        let requests = Dictionary(uniqueKeysWithValues: mockCenter.pendingRequests.map { ($0.identifier, $0) })
        #expect(requests[stage1.id]?.userInfo["notificationUrgency"] == AlertNotificationUrgency.active.rawValue)
        #expect(requests[stage2.id]?.userInfo["notificationUrgency"] == AlertNotificationUrgency.timeSensitive.rawValue)
        #expect(requests[stage1.id]?.soundIsNil == true)
        #expect(requests[stage2.id]?.soundIsNil == false)
    }

    @Test("Stage 1 category matches valid snooze durations")
    func stage1CategoryMatchesValidSnoozeDurations() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)
        let alert = try makeStage1NotificationTestAlert(fireDate: Date(timeIntervalSince1970: 1_800_000_000))

        await scheduler.scheduleNotification(for: alert, snoozeDurations: [60])

        let request = try #require(mockCenter.pendingRequests.first)
        #expect(request.categoryIdentifier == NotificationScheduler.stage1Snooze1Category)
        #expect(NotificationScheduler.stage1CategoryIdentifier(validSnoozeDurations: []) == NotificationScheduler
            .stage1AlertCategory)
        #expect(NotificationScheduler.stage1CategoryIdentifier(validSnoozeDurations: [60, 180]) == NotificationScheduler
            .stage1Snooze3Category)
    }
}

private func makeStage1NotificationTestAlert(fireDate: Date) throws -> ScheduledAlert {
    let eventStart = fireDate.addingTimeInterval(600)
    let eventEnd = eventStart.addingTimeInterval(1800)
    let joinURL = try #require(URL(string: "https://meet.google.com/stage-one"))
    let calendarURL = try #require(URL(string: "https://calendar.google.com/event?eid=stage-one"))

    return ScheduledAlert(
        id: "calendar-1::event-1-stage1",
        eventId: "calendar-1::event-1",
        stage: .stage1,
        scheduledFireTime: fireDate,
        eventTitle: "Early Warning Review",
        eventStartTime: eventStart,
        eventEndTime: eventEnd,
        joinURL: joinURL,
        calendarURL: calendarURL,
        notificationPayload: AlertNotificationPayload.make(
            eventTitle: "Early Warning Review",
            eventStartTime: eventStart,
            stage: .stage1
        )
    )
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
