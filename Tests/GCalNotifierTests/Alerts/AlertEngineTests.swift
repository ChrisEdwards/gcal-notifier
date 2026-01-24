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
        await engine.acknowledgeAlert(eventId: event.qualifiedId)

        let acknowledged = await engine.acknowledgedEvents
        #expect(acknowledged.contains(event.qualifiedId))

        let remaining = await engine.scheduledAlerts
        #expect(remaining.isEmpty)
    }

    @Test("Acknowledged events are not rescheduled")
    func acknowledgedEventsNotRescheduled() async throws {
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

        await engine.acknowledgeAlert(eventId: event.qualifiedId)
        await scheduler.reset()

        await engine.scheduleAlerts(for: [event], settings: settings)

        let scheduled = await scheduler.scheduledAlerts
        #expect(scheduled.isEmpty)
    }
}
