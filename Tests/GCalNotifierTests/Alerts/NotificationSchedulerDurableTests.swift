import Foundation
import Testing
@preconcurrency import UserNotifications
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
        let scheduler = await NotificationScheduler(
            center: mockCenter,
            delegate: delegate,
            timeSensitiveNotificationsEnabled: true
        )

        let fireDate = Date(timeIntervalSince1970: 1_800_000_000)
        let alert = try makeStage2NotificationTestAlert(fireDate: fireDate)

        await scheduler.scheduleNotification(for: alert)

        let request = try #require(mockCenter.pendingRequests.first)
        #expect(request.identifier == alert.id)
        #expect(request.title == alert.notificationPayload.title)
        #expect(request.body == alert.notificationPayload.body)
        #expect(request.body.contains(alert.eventTitle))
        #expect(request.categoryIdentifier == NotificationScheduler.stage2Snooze5Category)
        #expect(request.soundIsNil == false)
        #expect(request.isTimeSensitive)
    }

    @Test("Durable Stage 2 notification falls back to active without its entitlement")
    func durableStage2NotificationFallsBackToActiveWithoutEntitlement() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(
            center: mockCenter,
            delegate: delegate,
            timeSensitiveNotificationsEnabled: false
        )
        let alert = try makeStage2NotificationTestAlert(fireDate: Date(timeIntervalSince1970: 1_800_000_000))

        await scheduler.scheduleNotification(for: alert)

        let request = try #require(mockCenter.pendingRequests.first)
        #expect(request.isActive)
        #expect(!request.isTimeSensitive)
        #expect(request.soundIsNil == false)
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
        #expect(request.userInfo["contextLine"] == alert.contextLine)
        #expect(request.userInfo["snapshotFingerprint"] == alert.snapshotFingerprint)
        #expect(request.userInfo["notificationBody"] == alert.notificationPayload.body)
        #expect(request.userInfo["notificationCategory"] == request.categoryIdentifier)
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

    @Test("Stage 2 category matches valid snooze durations")
    func stage2CategoryMatchesValidSnoozeDurations() async throws {
        let mockCenter = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let scheduler = await NotificationScheduler(center: mockCenter, delegate: delegate)
        let alert = try makeStage2NotificationTestAlert(fireDate: Date(timeIntervalSince1970: 1_800_000_000))

        await scheduler.scheduleNotification(for: alert, snoozeDurations: [60, 180])

        let request = try #require(mockCenter.pendingRequests.first)
        #expect(request.categoryIdentifier == NotificationScheduler.stage2Snooze3Category)
        #expect(NotificationScheduler.stage2CategoryIdentifier(validSnoozeDurations: []) == NotificationScheduler
            .stage2AlertCategory)
        #expect(NotificationScheduler.stage2CategoryIdentifier(validSnoozeDurations: [60]) == NotificationScheduler
            .stage2Snooze1Category)
    }

    @Test("Registered stage categories expose Join Snooze and Dismiss actions")
    func registeredStageCategoriesExposeFullActionMatrix() throws {
        let stage1Actions = try actionIdentifiers(for: NotificationScheduler.stage1Snooze5Category)
        let stage2Actions = try actionIdentifiers(for: NotificationScheduler.stage2Snooze5Category)

        #expect(stage1Actions == [
            NotificationScheduler.stage1JoinActionIdentifier,
            NotificationScheduler.stage1Snooze1ActionIdentifier,
            NotificationScheduler.stage1Snooze3ActionIdentifier,
            NotificationScheduler.stage1Snooze5ActionIdentifier,
            NotificationScheduler.stage1DismissActionIdentifier,
        ])
        #expect(stage2Actions == [
            NotificationScheduler.stage2JoinActionIdentifier,
            NotificationScheduler.stage2Snooze1ActionIdentifier,
            NotificationScheduler.stage2Snooze3ActionIdentifier,
            NotificationScheduler.stage2Snooze5ActionIdentifier,
            NotificationScheduler.stage2DismissActionIdentifier,
        ])
    }
}

private func actionIdentifiers(for categoryIdentifier: String) throws -> [String] {
    let category = try #require(
        NotificationScheduler.registeredCategories.first { $0.identifier == categoryIdentifier }
    )
    return category.actions.map(\.identifier)
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
        contextLine: "5 attendees - Accepted",
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
        contextLine: "5 attendees - Accepted",
        notificationPayload: AlertNotificationPayload.make(
            eventTitle: "Cache Independent Review",
            eventStartTime: eventStart,
            stage: .stage2
        )
    )
}
