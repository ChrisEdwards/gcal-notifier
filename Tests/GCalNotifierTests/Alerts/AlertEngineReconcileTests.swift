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
        #expect(cancelled.contains("event-1-stage1"))
        #expect(cancelled.contains("event-1-stage2"))

        let remaining = await engine.scheduledAlerts
        let remainingEventIds = Set(remaining.map(\.eventId))
        #expect(!remainingEventIds.contains("event-1"))
        #expect(remainingEventIds.contains("event-2"))
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

        await engine.acknowledgeAlert(eventId: "event-1")
        await engine.acknowledgeAlert(eventId: "event-2")

        let event2 = makeAlertTestEvent(id: "event-2", startTime: eventStart)
        let settings = try makeAlertTestSettings()

        await engine.reconcile(newEvents: [event2], settings: settings)

        let acknowledged = await engine.acknowledgedEvents
        #expect(!acknowledged.contains("event-1"))
        #expect(acknowledged.contains("event-2"))
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
            eventId: "event-1",
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
            eventId: "event-1",
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
            eventId: "event-1",
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
        await scheduler.fireAlert(alertId: "event-1-stage1")

        try await Task.sleep(nanoseconds: 100_000_000)

        let delivered = await delivery.deliveredAlerts
        #expect(delivered.count == 1)
        #expect(delivered.first?.eventId == "event-1")
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
        #expect(alertIds.contains("event-1-stage1"))
        #expect(alertIds.contains("event-1-stage2"))
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
        await engine.cancelAlerts(for: "event-1")

        let persisted = try await store.load()
        #expect(persisted.isEmpty)
    }
}
