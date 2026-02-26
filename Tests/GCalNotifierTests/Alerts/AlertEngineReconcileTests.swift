import Foundation
import Testing
@testable import GCalNotifierCore

// MARK: - Reconcile Tests

@Suite("AlertEngine Reconcile Tests")
struct AlertEngineReconcileTests {
    @Test("Reconcile removes alerts for deleted events")
    func reconcileRemovesAlertsForDeletedEvents() async throws {
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

        let event1 = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let event2 = makeAlertTestEvent(id: "event-2", startTime: eventStart)
        let settings = try makeAlertTestSettings()

        await engine.scheduleAlerts(for: [event1, event2], settings: settings)
        await engine.reconcile(newEvents: [event2], settings: settings)

        let cancelled = await scheduler.cancelledAlertIds
        #expect(cancelled.contains(event1.alertIdentifier(for: .stage1)))
        #expect(cancelled.contains(event1.alertIdentifier(for: .stage2)))

        let remaining = await engine.scheduledAlerts
        let remainingEventIds = Set(remaining.map(\.eventId))
        #expect(!remainingEventIds.contains(event1.qualifiedId))
        #expect(remainingEventIds.contains(event2.qualifiedId))
    }

    @Test("Reconcile clears acknowledgments for deleted events")
    func reconcileClearsAcknowledgmentsForDeletedEvents() async throws {
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

        // Acknowledge alerts using alert IDs (eventId-stage format)
        let event1AlertId = "cal-1::event-1-stage1"
        let event2AlertId = "cal-1::event-2-stage1"
        await engine.acknowledgeAlert(alertId: event1AlertId, eventStartTime: eventStart)
        await engine.acknowledgeAlert(alertId: event2AlertId, eventStartTime: eventStart)

        let event2 = makeAlertTestEvent(id: "event-2", startTime: eventStart)
        let settings = try makeAlertTestSettings()

        await engine.reconcile(newEvents: [event2], settings: settings)

        // Event1's acknowledgment should be cleared (event deleted)
        // Event2's acknowledgment should remain (event still exists)
        let acknowledged = await engine.acknowledgedAlerts
        #expect(!acknowledged.contains(event1AlertId))
        #expect(acknowledged.contains(event2AlertId))
    }

    @Test("Reconcile clears acknowledgment when event time changes")
    func reconcileClearsAcknowledgmentWhenEventTimeChanges() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let initialStart = baseTime.addingTimeInterval(3600)
        let updatedStart = baseTime.addingTimeInterval(7200)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        let event = makeAlertTestEvent(id: "event-1", startTime: initialStart)
        let settings = try makeAlertTestSettings()

        await engine.scheduleAlerts(for: [event], settings: settings)

        let stage1AlertId = event.alertIdentifier(for: .stage1)
        await engine.acknowledgeAlert(alertId: stage1AlertId, eventStartTime: initialStart)
        await scheduler.reset()

        let updatedEvent = makeAlertTestEvent(id: "event-1", startTime: updatedStart)
        await engine.reconcile(newEvents: [updatedEvent], settings: settings)

        let scheduled = await scheduler.scheduledAlerts
        let scheduledIds = scheduled.map(\.alertId)
        #expect(scheduledIds.contains(updatedEvent.alertIdentifier(for: .stage1)))
        #expect(scheduledIds.contains(updatedEvent.alertIdentifier(for: .stage2)))

        let acknowledged = await engine.acknowledgedAlerts
        #expect(!acknowledged.contains(stage1AlertId))
    }

    @Test("Reconcile clears acknowledgments without prefix collisions")
    func reconcileClearsAcknowledgmentsWithoutPrefixCollisions() async throws {
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

        let event1AlertId = "cal-1::event-1-stage1"
        let event10AlertId = "cal-1::event-10-stage1"
        await engine.acknowledgeAlert(alertId: event1AlertId, eventStartTime: eventStart)
        await engine.acknowledgeAlert(alertId: event10AlertId, eventStartTime: eventStart)

        let event1 = makeAlertTestEvent(id: "event-1", startTime: eventStart)
        let settings = try makeAlertTestSettings()

        await engine.reconcile(newEvents: [event1], settings: settings)

        let acknowledged = await engine.acknowledgedAlerts
        #expect(acknowledged.contains(event1AlertId))
        #expect(!acknowledged.contains(event10AlertId))
    }

    @Test("Reconcile cancels stage alerts when stage is disabled")
    func reconcileCancelsDisabledStageAlerts() async throws {
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
        let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 2)

        await engine.scheduleAlerts(for: [event], settings: settings)

        // Disable stage 1 alerts and reconcile
        settings.alertStage1Minutes = 0
        await engine.reconcile(newEvents: [event], settings: settings)

        let cancelled = await scheduler.cancelledAlertIds
        #expect(cancelled.contains(event.alertIdentifier(for: .stage1)))

        let remaining = await engine.scheduledAlerts
        #expect(remaining.count == 1)
        #expect(remaining.first?.stage == .stage2)
    }

    @Test("Reconcile cancels alerts when calendar is disabled")
    func reconcileCancelsAlertsWhenCalendarDisabled() async throws {
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
        let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 2)

        await engine.scheduleAlerts(for: [event], settings: settings)

        // Disable the calendar and reconcile
        settings.enabledCalendars = ["cal-2"]
        await engine.reconcile(newEvents: [event], settings: settings)

        let cancelled = await scheduler.cancelledAlertIds
        #expect(cancelled.contains(event.alertIdentifier(for: .stage1)))
        #expect(cancelled.contains(event.alertIdentifier(for: .stage2)))

        let remaining = await engine.scheduledAlerts
        #expect(remaining.isEmpty)
    }
}

// MARK: - Reconcile on Relaunch Tests

@Suite("AlertEngine Reconcile on Relaunch Tests")
struct AlertEngineReconcileOnRelaunchTests {
    @Test("Reconcile on relaunch recovers scheduled alerts")
    func reconcileOnRelaunchRecoversScheduledAlerts() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let futureFireTime = baseTime.addingTimeInterval(1800)

        let alert = ScheduledAlert(
            id: "persisted-alert",
            eventId: "cal-1::event-1",
            stage: .stage1,
            scheduledFireTime: futureFireTime,
            snoozeCount: 0,
            originalFireTime: nil,
            eventTitle: "Persisted Meeting",
            eventStartTime: futureFireTime.addingTimeInterval(600)
        )

        let store = ScheduledAlertsStore(fileURL: fileURL)
        try await store.save([alert])

        let newStore = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let engine = AlertEngine(
            alertsStore: newStore, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        try await engine.reconcileOnRelaunch()

        let scheduled = await scheduler.scheduledAlerts
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.alertId == "persisted-alert")
        #expect(scheduled.first?.fireDate == futureFireTime)

        let recovered = await engine.scheduledAlerts
        #expect(recovered.count == 1)
    }

    @Test("Reconcile on relaunch skips past alerts")
    func reconcileOnRelaunchSkipsPastAlerts() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let pastFireTime = baseTime.addingTimeInterval(-1800)

        let alert = ScheduledAlert(
            id: "past-alert",
            eventId: "cal-1::event-1",
            stage: .stage1,
            scheduledFireTime: pastFireTime,
            snoozeCount: 0,
            originalFireTime: nil,
            eventTitle: "Past Meeting",
            eventStartTime: pastFireTime.addingTimeInterval(600)
        )

        let store = ScheduledAlertsStore(fileURL: fileURL)
        try await store.save([alert])

        let newStore = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let engine = AlertEngine(
            alertsStore: newStore, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        try await engine.reconcileOnRelaunch()

        let scheduled = await scheduler.scheduledAlerts
        #expect(scheduled.isEmpty)

        let recovered = await engine.scheduledAlerts
        #expect(recovered.isEmpty)
    }

    @Test("Reconcile on relaunch only runs once")
    func reconcileOnRelaunchOnlyRunsOnce() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let futureFireTime = baseTime.addingTimeInterval(1800)

        let alert = ScheduledAlert(
            id: "persisted-alert",
            eventId: "cal-1::event-1",
            stage: .stage1,
            scheduledFireTime: futureFireTime,
            snoozeCount: 0,
            originalFireTime: nil,
            eventTitle: "Persisted Meeting",
            eventStartTime: futureFireTime.addingTimeInterval(600)
        )

        let store = ScheduledAlertsStore(fileURL: fileURL)
        try await store.save([alert])

        let newStore = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()

        let engine = AlertEngine(
            alertsStore: newStore, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        try await engine.reconcileOnRelaunch()
        try await engine.reconcileOnRelaunch()

        let scheduled = await scheduler.scheduledAlerts
        #expect(scheduled.count == 1)
    }

    @Test("Reconcile on relaunch retries after load failure")
    func reconcileOnRelaunchRetriesAfterLoadFailure() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let invalidData = Data("not-json".utf8)
        try invalidData.write(to: fileURL)

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let scheduler = MockAlertScheduler()
        let delivery = MockAlertDelivery()
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        let engine = AlertEngine(
            alertsStore: store, scheduler: scheduler, delivery: delivery,
            dateProvider: { baseTime }
        )

        var didThrow = false
        do {
            try await engine.reconcileOnRelaunch()
        } catch {
            didThrow = true
        }
        #expect(didThrow)

        let futureFireTime = baseTime.addingTimeInterval(1800)
        let alert = ScheduledAlert(
            id: "recovery-alert",
            eventId: "cal-1::event-1",
            stage: .stage1,
            scheduledFireTime: futureFireTime,
            snoozeCount: 0,
            originalFireTime: nil,
            eventTitle: "Recovered Meeting",
            eventStartTime: futureFireTime.addingTimeInterval(600)
        )

        try await store.save([alert])
        try await engine.reconcileOnRelaunch()

        let scheduled = await scheduler.scheduledAlerts
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.alertId == "recovery-alert")
    }
}

// MARK: - Alert Delivery Tests

@Suite("AlertEngine Alert Delivery Tests")
struct AlertEngineAlertDeliveryTests {
    @Test("Alert fires and delivers")
    func alertFiresAndDelivers() async throws {
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

        let event = makeAlertTestEvent(id: "event-1", title: "Important Meeting", startTime: eventStart)
        let settings = try makeAlertTestSettings()

        await engine.scheduleAlerts(for: [event], settings: settings)
        await scheduler.fireAlert(alertId: event.alertIdentifier(for: .stage1))

        try await Task.sleep(nanoseconds: 100_000_000)

        let delivered = await delivery.deliveredAlerts
        #expect(delivered.count == 1)
        #expect(delivered.first?.eventId == event.qualifiedId)
        #expect(delivered.first?.stage == .stage1)
        #expect(delivered.first?.eventTitle == "Important Meeting")
    }
}

// MARK: - Persistence Tests

@Suite("AlertEngine Persistence Tests")
struct AlertEnginePersistenceTests {
    @Test("Alerts are persisted after scheduling")
    func alertsPersistedAfterScheduling() async throws {
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

        let persisted = try await store.load()
        #expect(persisted.count == 2)

        let alertIds = Set(persisted.map(\.id))
        #expect(alertIds.contains(event.alertIdentifier(for: .stage1)))
        #expect(alertIds.contains(event.alertIdentifier(for: .stage2)))
    }

    @Test("Alerts are removed from persistence after cancellation")
    func alertsRemovedFromPersistenceAfterCancellation() async throws {
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

        let persisted = try await store.load()
        #expect(persisted.isEmpty)
    }
}
