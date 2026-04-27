import Foundation
import Testing
@testable import GCalNotifierCore

// MARK: - Schedule Alerts Tests

@Suite("AlertEngine Schedule Alerts Tests")
struct AlertEngineScheduleAlertsTests {
    @Test("Schedule alerts creates stage 1 and stage 2")
    func scheduleAlertsCreatesStage1AndStage2() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(3600)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let settings = try makeAlertTestSettings()

        await engine.scheduleAlerts(for: [event], settings: settings)

        let scheduled = await scheduler.scheduledAlerts
        #expect(scheduled.count == 2)

        let alertIds = scheduled.map(\.alertId)
        #expect(alertIds.contains(event.alertIdentifier(for: .stage1)))
        #expect(alertIds.contains(event.alertIdentifier(for: .stage2)))
    }

    @Test("Schedule alerts persists Stage 2 snapshot and durable notification")
    func scheduleAlertsPersistsStage2SnapshotAndDurableNotification() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let durableScheduler = MockDurableAlertNotificationScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_800_000_000)
        let eventStart = baseTime.addingTimeInterval(3600)
        let joinURL = try #require(URL(string: "https://meet.google.com/vertical-slice"))
        let calendarURL = try #require(URL(string: "https://calendar.google.com/event?eid=vertical-slice"))

        let engine = AlertEngine(
            alertsStore: store,
            scheduler: scheduler,
            delivery: delivery,
            durableNotificationScheduler: durableScheduler,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(
            id: "event-1",
            title: "Durable Stage 2 Meeting",
            startTime: eventStart,
            meetingLinks: [MeetingLink(url: joinURL)],
            htmlLink: calendarURL
        )
        let settings = try makeAlertTestSettings()

        await engine.scheduleAlerts(for: [event], settings: settings)

        let persistedStage2 = try #require(try await store.load().first { $0.stage == .stage2 })
        expectStage2Snapshot(
            persistedStage2,
            event: event,
            fireTime: eventStart.addingTimeInterval(-2 * 60),
            joinURL: joinURL,
            calendarURL: calendarURL
        )
        let durableNotifications = await durableScheduler.scheduledNotifications
        expectDurableNotifications(durableNotifications, match: persistedStage2)
    }

    @Test("Schedule alerts with stage 1 disabled only schedules stage 2")
    func scheduleAlertsStage1DisabledOnlySchedulesStage2() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(3600)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 2)

        await engine.scheduleAlerts(for: [event], settings: settings)

        let scheduled = await scheduler.scheduledAlerts
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.alertId == event.alertIdentifier(for: .stage2))
    }

    @Test("Schedule alerts fires at correct time")
    func scheduleAlertsFiresAtCorrectTime() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(3600)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let settings = try makeAlertTestSettings()

        await engine.scheduleAlerts(for: [event], settings: settings)

        let scheduled = await scheduler.scheduledAlerts

        let stage1 = scheduled.first { $0.alertId == event.alertIdentifier(for: .stage1) }
        let expectedStage1 = eventStart.addingTimeInterval(-10 * 60)
        #expect(stage1?.fireDate == expectedStage1)

        let stage2 = scheduled.first { $0.alertId == event.alertIdentifier(for: .stage2) }
        let expectedStage2 = eventStart.addingTimeInterval(-2 * 60)
        #expect(stage2?.fireDate == expectedStage2)
    }

    @Test("Schedule alerts for event too soon skips passed stages")
    func scheduleAlertsEventTooSoonSkipsPassedStages() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(5 * 60)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let settings = try makeAlertTestSettings()

        await engine.scheduleAlerts(for: [event], settings: settings)

        let scheduled = await scheduler.scheduledAlerts
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.alertId == event.alertIdentifier(for: .stage2))
    }

    @Test("Schedule alerts within grace period fires immediately")
    func scheduleAlertsWithinGracePeriodFiresImmediately() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(9 * 60)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 0)

        await engine.scheduleAlerts(for: [event], settings: settings)

        let scheduled = await scheduler.scheduledAlerts
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.alertId == event.alertIdentifier(for: .stage1))
        #expect(scheduled.first?.fireDate == baseTime)
    }

    @Test("Schedule alerts for event already started schedules nothing")
    func scheduleAlertsEventAlreadyStartedSchedulesNothing() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(-5 * 60)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let settings = try makeAlertTestSettings()

        await engine.scheduleAlerts(for: [event], settings: settings)

        let scheduled = await scheduler.scheduledAlerts
        #expect(scheduled.isEmpty)
    }

    @Test("Schedule alerts skips events without meeting links")
    func scheduleAlertsSkipsEventsWithoutMeetingLinks() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(3600)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart, meetingLinks: [])
        let settings = try makeAlertTestSettings()

        await engine.scheduleAlerts(for: [event], settings: settings)

        let scheduled = await scheduler.scheduledAlerts
        #expect(scheduled.isEmpty)
    }

    @Test("Schedule alerts skips all-day events")
    func scheduleAlertsSkipsAllDayEvents() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(3600)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart, isAllDay: true)
        let settings = try makeAlertTestSettings()

        await engine.scheduleAlerts(for: [event], settings: settings)

        let scheduled = await scheduler.scheduledAlerts
        #expect(scheduled.isEmpty)
    }
}

// MARK: - Cancel Alerts Tests

@Suite("AlertEngine Cancel Alerts Tests")
struct AlertEngineCancelAlertsTests {
    @Test("Cancel alerts removes alerts for event")
    func cancelAlertsRemovesForEvent() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(3600)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let settings = try makeAlertTestSettings()

        await engine.scheduleAlerts(for: [event], settings: settings)
        await engine.cancelAlerts(for: event.qualifiedId)

        let cancelled = await scheduler.cancelledAlertIds
        #expect(cancelled.contains(event.alertIdentifier(for: .stage1)))
        #expect(cancelled.contains(event.alertIdentifier(for: .stage2)))

        let remaining = await engine.scheduledAlerts
        #expect(remaining.isEmpty)
    }
}

// MARK: - Acknowledge Alert Tests

@Suite("AlertEngine Acknowledge Alert Tests")
struct AlertEngineAcknowledgeAlertTests {
    @Test("Acknowledge marks event as acknowledged")
    func acknowledgeMarksEventAcknowledged() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(3600)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let settings = try makeAlertTestSettings()

        await engine.scheduleAlerts(for: [event], settings: settings)

        // Acknowledge stage1 alert - stage2 should remain
        let stage1AlertId = event.alertIdentifier(for: .stage1)
        await engine.acknowledgeAlert(alertId: stage1AlertId, eventStartTime: event.startTime)

        let acknowledged = await engine.acknowledgedAlerts
        #expect(acknowledged.contains(stage1AlertId))

        // Only the acknowledged stage is removed; other stage remains
        let remaining = await engine.scheduledAlerts
        #expect(remaining.count == 1)
        #expect(remaining.first?.stage == .stage2)
    }

    @Test("Acknowledged alert stage is not rescheduled, but other stage is")
    func acknowledgedAlertNotRescheduled() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(3600)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let settings = try makeAlertTestSettings()

        // Acknowledge only stage1 before scheduling
        let stage1AlertId = event.alertIdentifier(for: .stage1)
        await engine.acknowledgeAlert(alertId: stage1AlertId, eventStartTime: event.startTime)
        await scheduler.reset()

        await engine.scheduleAlerts(for: [event], settings: settings)

        // Stage1 should not be scheduled, but stage2 should be
        let scheduled = await scheduler.scheduledAlerts
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.alertId.contains("stage2") == true)
    }
}

private func expectStage2Snapshot(
    _ alert: ScheduledAlert,
    event: CalendarEvent,
    fireTime: Date,
    joinURL: URL,
    calendarURL: URL
) {
    #expect(alert.eventTitle == event.title)
    #expect(alert.eventStartTime == event.startTime)
    #expect(alert.eventEndTime == event.endTime)
    #expect(alert.scheduledFireTime == fireTime)
    #expect(alert.joinURL == joinURL)
    #expect(alert.calendarURL == calendarURL)
    #expect(alert.notificationPayload.categoryIdentifier == AlertNotificationPayload.stage2CategoryIdentifier)
    #expect(alert.notificationPayload.soundBehavior == .defaultSound)
    #expect(alert.notificationPayload.urgency == .timeSensitive)
}

private func expectDurableNotifications(
    _ durableNotifications: [ScheduledAlert],
    match persistedStage2: ScheduledAlert
) {
    #expect(durableNotifications.count == 1)
    #expect(durableNotifications.first?.id == persistedStage2.id)
    #expect(durableNotifications.first?.notificationPayload == persistedStage2.notificationPayload)
}
