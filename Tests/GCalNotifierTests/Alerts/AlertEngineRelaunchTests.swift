import Foundation
import Testing
@testable import GCalNotifierCore

@Suite("AlertEngine Reconcile on Relaunch Tests")
struct AlertEngineReconcileOnRelaunchTests {
    @Test("Reconcile on relaunch recovers scheduled alerts")
    func reconcileOnRelaunchRecoversScheduledAlerts() async throws {
        let context = try await makeRelaunchContext(alert: makeFutureRelaunchAlert())
        defer { cleanupAlertTestTempDir(context.fileURL) }

        try await context.engine.reconcileOnRelaunch()

        let scheduled = await context.scheduler.scheduledAlerts
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.alertId == "persisted-alert")
        #expect(scheduled.first?.fireDate == context.alert.scheduledFireTime)
        #expect(await context.engine.scheduledAlerts.count == 1)
        #expect(await context.durableScheduler.scheduledNotifications.map(\.id) == ["persisted-alert"])
    }

    @Test("Reconcile on relaunch skips obsolete past alerts")
    func reconcileOnRelaunchSkipsObsoletePastAlerts() async throws {
        let context = try await makeRelaunchContext(alert: makeObsoletePastRelaunchAlert())
        defer { cleanupAlertTestTempDir(context.fileURL) }

        try await context.engine.reconcileOnRelaunch()

        #expect(await context.scheduler.scheduledAlerts.isEmpty)
        #expect(await context.engine.scheduledAlerts.isEmpty)
    }

    @Test("Reconcile on relaunch preserves overdue relevant alerts without modal trigger")
    func reconcileOnRelaunchPreservesOverdueRelevantAlertsWithoutModalTrigger() async throws {
        let context = try await makeRelaunchContext(alert: makeOverdueRelevantRelaunchAlert())
        defer { cleanupAlertTestTempDir(context.fileURL) }

        try await context.engine.reconcileOnRelaunch()

        #expect(await context.engine.scheduledAlerts.map(\.id) == ["delivered-alert"])
        #expect(await context.scheduler.scheduledAlerts.isEmpty)
        #expect(await context.durableScheduler.scheduledNotifications.isEmpty)
        #expect(await context.durableScheduler.cancelledNotificationIds.isEmpty)
    }

    @Test("Reconcile on relaunch only runs once")
    func reconcileOnRelaunchOnlyRunsOnce() async throws {
        let context = try await makeRelaunchContext(alert: makeFutureRelaunchAlert())
        defer { cleanupAlertTestTempDir(context.fileURL) }

        try await context.engine.reconcileOnRelaunch()
        try await context.engine.reconcileOnRelaunch()

        #expect(await context.scheduler.scheduledAlerts.count == 1)
    }

    @Test("Reconcile on relaunch retries after load failure")
    func reconcileOnRelaunchRetriesAfterLoadFailure() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        try Data("not-json".utf8).write(to: fileURL)
        let context = makeRelaunchContext(fileURL: fileURL)

        do {
            try await context.engine.reconcileOnRelaunch()
            Issue.record("Expected relaunch load failure")
        } catch {}

        let alert = makeFutureRelaunchAlert(id: "recovery-alert", title: "Recovered Meeting")
        try await context.store.save([alert])
        try await context.engine.reconcileOnRelaunch()

        let scheduled = await context.scheduler.scheduledAlerts
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.alertId == "recovery-alert")
    }
}

private struct RelaunchContext {
    let fileURL: URL
    let store: ScheduledAlertsStore
    let scheduler: MockAlertScheduler
    let durableScheduler: MockDurableAlertNotificationScheduler
    let engine: AlertEngine
    let alert: ScheduledAlert
}

private func makeRelaunchContext(alert: ScheduledAlert) async throws -> RelaunchContext {
    let fileURL = makeAlertTestTempFileURL()
    let context = makeRelaunchContext(fileURL: fileURL, alert: alert)
    try await context.store.save([alert])
    return context
}

private func makeRelaunchContext(
    fileURL: URL,
    alert: ScheduledAlert = makeFutureRelaunchAlert()
) -> RelaunchContext {
    let store = ScheduledAlertsStore(fileURL: fileURL)
    let scheduler = MockAlertScheduler()
    let durableScheduler = MockDurableAlertNotificationScheduler()
    let engine = AlertEngine(
        alertsStore: store,
        scheduler: scheduler,
        delivery: MockAlertDelivery(),
        durableNotificationScheduler: durableScheduler,
        dateProvider: { relaunchBaseTime }
    )
    return RelaunchContext(
        fileURL: fileURL,
        store: store,
        scheduler: scheduler,
        durableScheduler: durableScheduler,
        engine: engine,
        alert: alert
    )
}

private let relaunchBaseTime = Date(timeIntervalSince1970: 1_700_000_000)

private func makeFutureRelaunchAlert(
    id: String = "persisted-alert",
    title: String = "Persisted Meeting"
) -> ScheduledAlert {
    let fireTime = relaunchBaseTime.addingTimeInterval(1800)
    return ScheduledAlert(
        id: id,
        eventId: "cal-1::event-1",
        stage: .stage1,
        scheduledFireTime: fireTime,
        eventTitle: title,
        eventStartTime: fireTime.addingTimeInterval(600)
    )
}

private func makeObsoletePastRelaunchAlert() -> ScheduledAlert {
    let fireTime = relaunchBaseTime.addingTimeInterval(-1800)
    return ScheduledAlert(
        id: "past-alert",
        eventId: "cal-1::event-1",
        stage: .stage1,
        scheduledFireTime: fireTime,
        eventTitle: "Past Meeting",
        eventStartTime: fireTime.addingTimeInterval(600)
    )
}

private func makeOverdueRelevantRelaunchAlert() -> ScheduledAlert {
    let fireTime = relaunchBaseTime.addingTimeInterval(-60)
    return ScheduledAlert(
        id: "delivered-alert",
        eventId: "cal-1::event-1",
        stage: .stage2,
        scheduledFireTime: fireTime,
        eventTitle: "Delivered Meeting",
        eventStartTime: relaunchBaseTime.addingTimeInterval(60),
        eventEndTime: relaunchBaseTime.addingTimeInterval(1800)
    )
}
