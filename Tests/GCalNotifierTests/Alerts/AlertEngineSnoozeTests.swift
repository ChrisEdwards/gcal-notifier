import Foundation
import Testing

@testable import GCalNotifierCore

// MARK: - Snooze Tests

@Suite("AlertEngine Snooze Tests")
struct AlertEngineSnoozeTests {
    @Test("Snooze reschedules alert with new fire time")
    func snoozeReschedulesAlertWithNewFireTime() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(600) // 10 min from now

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let alertId = event.alertIdentifier(for: .stage2)
        let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 5)

        await engine.scheduleAlerts(for: [event], settings: settings)

        // Snooze for 1 minute
        try await engine.snooze(alertId: alertId, duration: 60)

        let scheduled = await scheduler.scheduledAlerts
        // Original + snoozed = 2 calls, but we check the latest
        let lastScheduled = scheduled.last
        #expect(lastScheduled?.alertId == alertId)
        #expect(lastScheduled?.fireDate == baseTime.addingTimeInterval(60))
    }

    @Test("Snooze increments snooze count")
    func snoozeIncrementsSnoozeCount() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(600)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let alertId = event.alertIdentifier(for: .stage2)
        let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 5)

        await engine.scheduleAlerts(for: [event], settings: settings)

        // Snooze once
        try await engine.snooze(alertId: alertId, duration: 60)

        let alerts = await engine.scheduledAlerts
        let snoozedAlert = alerts.first { $0.id == alertId }
        #expect(snoozedAlert?.snoozeCount == 1)
    }

    @Test("Snooze preserves original fire time")
    func snoozePreservesOriginalFireTime() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(600)
        let originalFireTime = eventStart.addingTimeInterval(-300) // 5 min before

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let alertId = event.alertIdentifier(for: .stage2)
        let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 5)

        await engine.scheduleAlerts(for: [event], settings: settings)

        // Snooze twice
        try await engine.snooze(alertId: alertId, duration: 60)
        try await engine.snooze(alertId: alertId, duration: 60)

        let alerts = await engine.scheduledAlerts
        let snoozedAlert = alerts.first { $0.id == alertId }
        #expect(snoozedAlert?.snoozeCount == 2)
        #expect(snoozedAlert?.originalFireTime == originalFireTime)
    }

    @Test("Snooze throws error for non-existent alert")
    func snoozeThrowsErrorForNonExistentAlert() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        await #expect(throws: AlertError.alertNotFound(alertId: "non-existent")) {
            try await engine.snooze(alertId: "non-existent", duration: 60)
        }
    }

    @Test("Snooze throws error if meeting already started")
    func snoozeThrowsErrorIfMeetingAlreadyStarted() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(600) // 10 min from now

        // Use nonisolated(unsafe) for mutable time to allow Sendable closure
        nonisolated(unsafe) var currentTime = baseTime
        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { currentTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let alertId = event.alertIdentifier(for: .stage2)
        let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 5)

        await engine.scheduleAlerts(for: [event], settings: settings)

        // Advance time past meeting start
        currentTime = eventStart.addingTimeInterval(60)

        await #expect(throws: AlertError.meetingAlreadyStarted) {
            try await engine.snooze(alertId: alertId, duration: 60)
        }
    }

    @Test("Snooze throws error if snooze would exceed meeting start")
    func snoozeThrowsErrorIfSnoozeWouldExceedMeetingStart() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(120) // 2 min from now

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let alertId = event.alertIdentifier(for: .stage2)
        let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 1)

        await engine.scheduleAlerts(for: [event], settings: settings)

        // Try to snooze for 3 minutes (would exceed meeting start)
        await #expect(throws: AlertError.snoozePastMeetingStart) {
            try await engine.snooze(alertId: alertId, duration: 180)
        }
    }

    @Test("Snooze cancels existing timer before rescheduling")
    func snoozeCancelsExistingTimerBeforeRescheduling() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(600)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let alertId = event.alertIdentifier(for: .stage2)
        let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 5)

        await engine.scheduleAlerts(for: [event], settings: settings)

        try await engine.snooze(alertId: alertId, duration: 60)

        let cancelled = await scheduler.cancelledAlertIds
        #expect(cancelled.contains(alertId))
    }

    @Test("Snooze persists the snoozed alert")
    func snoozePersistsTheSnoozedAlert() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(600)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let alertId = event.alertIdentifier(for: .stage2)
        let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 5)

        await engine.scheduleAlerts(for: [event], settings: settings)

        try await engine.snooze(alertId: alertId, duration: 60)

        let persisted = try await store.load()
        let snoozedAlert = persisted.first { $0.id == alertId }
        #expect(snoozedAlert?.snoozeCount == 1)
        #expect(snoozedAlert?.scheduledFireTime == baseTime.addingTimeInterval(60))
    }

    @Test("Snooze works after alert fires - alert remains in dictionary during delivery")
    func snoozeWorksAfterAlertFires() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let eventStart = baseTime.addingTimeInterval(600) // 10 min from now

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let alertId = event.alertIdentifier(for: .stage2)
        let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 5)

        await engine.scheduleAlerts(for: [event], settings: settings)

        // Simulate alert firing (as if the timer went off)
        await scheduler.fireAlert(alertId: alertId)

        // Small delay to let async handler complete
        try await Task.sleep(for: .milliseconds(50))

        // Verify alert was delivered
        let delivered = await delivery.deliveredAlerts
        #expect(delivered.count == 1)
        #expect(delivered.first?.id == alertId)

        // Now try to snooze - this should work because the alert should still be in the dictionary
        // (The bug was that the alert was removed before delivery, breaking snooze)
        try await engine.snooze(alertId: alertId, duration: 60)

        // Verify snooze worked
        let alerts = await engine.scheduledAlerts
        let snoozedAlert = alerts.first { $0.id == alertId }
        #expect(snoozedAlert != nil, "Alert should still exist after snooze")
        #expect(snoozedAlert?.snoozeCount == 1)
    }
}
