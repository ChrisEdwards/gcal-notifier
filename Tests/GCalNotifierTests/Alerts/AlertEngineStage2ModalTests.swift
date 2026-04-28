import Foundation
import Testing
@testable import GCalNotifierCore

@Suite("AlertEngine Stage 2 Modal Tests")
struct AlertEngineStage2ModalTests {
    @Test("Stage 2 schedules durable notification and local modal trigger")
    func stage2SchedulesDurableNotificationAndLocalModalTrigger() async throws {
        let context = try makeStage2ModalContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)

        let scheduled = await context.scheduler.scheduledAlerts
        let durable = await context.durableScheduler.scheduledNotifications
        #expect(scheduled.contains { $0.alertId == context.alertId })
        #expect(durable.map(\.id) == [context.alertId])
    }

    @Test("Fresh Stage 2 local trigger delivers modal without acknowledging")
    func freshStage2LocalTriggerDeliversModalWithoutAcknowledging() async throws {
        nonisolated(unsafe) var currentTime = stage2ModalBaseTime
        let context = try makeStage2ModalContext(dateProvider: { currentTime })
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        currentTime = context.stage2FireTime
        try await fireFirstStage2Handler(context)

        let delivered = await context.delivery.deliveredAlerts
        let remaining = await context.engine.scheduledAlerts
        let cancelledNotifications = await context.durableScheduler.cancelledNotificationIds
        #expect(delivered.map(\.id) == [context.alertId])
        #expect(remaining.contains { $0.id == context.alertId })
        #expect(cancelledNotifications.isEmpty)
    }

    @Test("Stale Stage 2 local trigger no-ops")
    func staleStage2LocalTriggerNoOps() async throws {
        nonisolated(unsafe) var currentTime = stage2ModalBaseTime
        let context = try makeStage2ModalContext(dateProvider: { currentTime })
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        currentTime = context.stage2FireTime.addingTimeInterval(2 * 60 * 60)
        try await fireFirstStage2Handler(context)

        let delivered = await context.delivery.deliveredAlerts
        let remaining = await context.engine.scheduledAlerts
        let removedDeliveredNotifications = await context.durableScheduler.removedDeliveredNotificationIds
        #expect(delivered.isEmpty)
        #expect(remaining.contains { $0.id == context.alertId })
        #expect(removedDeliveredNotifications.isEmpty)
    }

    @Test("Wake reconciliation preserves delivered notification for relevant past alert")
    func wakeReconciliationPreservesDeliveredNotificationForRelevantPastAlert() async throws {
        nonisolated(unsafe) var currentTime = stage2ModalBaseTime
        let context = try makeStage2ModalContext(dateProvider: { currentTime })
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        await context.scheduler.reset()
        await context.durableScheduler.reset()

        currentTime = context.stage2FireTime.addingTimeInterval(60)
        await context.engine.reconcile(newEvents: [context.event], settings: context.settings)

        let remaining = await context.engine.scheduledAlerts
        #expect(remaining.contains { $0.id == context.alertId })
        #expect(await context.scheduler.cancelledAlertIds.isEmpty)
        #expect(await context.scheduler.scheduledAlerts.isEmpty)
        #expect(await context.durableScheduler.cancelledNotificationIds.isEmpty)
        #expect(await context.durableScheduler.removedDeliveredNotificationIds.isEmpty)
        #expect(await context.durableScheduler.scheduledNotifications.isEmpty)
    }

    @Test("Acknowledged Stage 2 local trigger no-ops")
    func acknowledgedStage2LocalTriggerNoOps() async throws {
        let context = try makeStage2ModalContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        await context.engine.acknowledgeAlert(alertId: context.alertId, eventStartTime: context.event.startTime)
        try await fireFirstStage2Handler(context)

        let delivered = await context.delivery.deliveredAlerts
        #expect(delivered.isEmpty)
    }

    @Test("Snoozed Stage 2 old local trigger no-ops")
    func snoozedStage2OldLocalTriggerNoOps() async throws {
        let context = try makeStage2ModalContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        try await context.engine.snooze(alertId: context.alertId, duration: 60)
        try await fireFirstStage2Handler(context)

        let delivered = await context.delivery.deliveredAlerts
        #expect(delivered.isEmpty)
    }
}

@Suite("AlertEngine Stage 1 Modal Tests")
struct AlertEngineStage1ModalTests {
    @Test("Stage 1 schedules durable notification and local modal trigger")
    func stage1SchedulesDurableNotificationAndLocalModalTrigger() async throws {
        let context = try makeStage1ModalContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)

        let scheduled = await context.scheduler.scheduledAlerts
        let durable = await context.durableScheduler.scheduledNotifications
        #expect(scheduled.contains { $0.alertId == context.alertId })
        #expect(durable.contains { $0.id == context.alertId })
    }

    @Test("Fresh Stage 1 local trigger delivers modal without acknowledging")
    func freshStage1LocalTriggerDeliversModalWithoutAcknowledging() async throws {
        nonisolated(unsafe) var currentTime = stage1ModalBaseTime
        let context = try makeStage1ModalContext(dateProvider: { currentTime })
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        currentTime = context.stage1FireTime
        try await fireFirstStage1Handler(context)

        let delivered = await context.delivery.deliveredAlerts
        let remaining = await context.engine.scheduledAlerts
        #expect(delivered.map(\.id) == [context.alertId])
        #expect(remaining.contains { $0.id == context.alertId })
    }

    @Test("Stale Stage 1 local trigger no-ops at Stage 2 fire time")
    func staleStage1LocalTriggerNoOpsAtStage2FireTime() async throws {
        nonisolated(unsafe) var currentTime = stage1ModalBaseTime
        let context = try makeStage1ModalContext(dateProvider: { currentTime })
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        currentTime = context.stage2FireTime
        try await fireFirstStage1Handler(context)

        let delivered = await context.delivery.deliveredAlerts
        #expect(delivered.isEmpty)
    }
}

private let stage2ModalBaseTime = Date(timeIntervalSince1970: 1_800_100_000)
private let stage1ModalBaseTime = Date(timeIntervalSince1970: 1_800_600_000)

private struct Stage2ModalTestContext {
    let fileURL: URL
    let settings: SettingsStore
    let scheduler: MockAlertScheduler
    let durableScheduler: MockDurableAlertNotificationScheduler
    let delivery: MockAlertDelivery
    let engine: AlertEngine
    let event: CalendarEvent
    let alertId: String
    let stage2FireTime: Date
}

private func makeStage2ModalContext(
    dateProvider: @escaping @Sendable () -> Date = { stage2ModalBaseTime }
) throws -> Stage2ModalTestContext {
    let fileURL = makeAlertTestTempFileURL()
    let store = ScheduledAlertsStore(fileURL: fileURL)
    let scheduler = MockAlertScheduler()
    let durableScheduler = MockDurableAlertNotificationScheduler()
    let delivery = MockAlertDelivery()
    let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 5)
    let eventStart = stage2ModalBaseTime.addingTimeInterval(10 * 60)
    let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
    let engine = AlertEngine(
        alertsStore: store,
        scheduler: scheduler,
        delivery: delivery,
        durableNotificationScheduler: durableScheduler,
        dateProvider: dateProvider
    )

    return Stage2ModalTestContext(
        fileURL: fileURL,
        settings: settings,
        scheduler: scheduler,
        durableScheduler: durableScheduler,
        delivery: delivery,
        engine: engine,
        event: event,
        alertId: event.alertIdentifier(for: .stage2),
        stage2FireTime: eventStart.addingTimeInterval(-5 * 60)
    )
}

private func fireFirstStage2Handler(_ context: Stage2ModalTestContext) async throws {
    let handler = try #require(await context.scheduler.firstHandler(alertId: context.alertId))
    handler()
    try await Task.sleep(for: .milliseconds(50))
}

private struct Stage1ModalTestContext {
    let fileURL: URL
    let settings: SettingsStore
    let scheduler: MockAlertScheduler
    let durableScheduler: MockDurableAlertNotificationScheduler
    let delivery: MockAlertDelivery
    let engine: AlertEngine
    let event: CalendarEvent
    let alertId: String
    let stage1FireTime: Date
    let stage2FireTime: Date
}

private func makeStage1ModalContext(
    dateProvider: @escaping @Sendable () -> Date = { stage1ModalBaseTime }
) throws -> Stage1ModalTestContext {
    let fileURL = makeAlertTestTempFileURL()
    let scheduler = MockAlertScheduler()
    let durableScheduler = MockDurableAlertNotificationScheduler()
    let delivery = MockAlertDelivery()
    let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 2)
    let eventStart = stage1ModalBaseTime.addingTimeInterval(20 * 60)
    let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
    let engine = AlertEngine(
        alertsStore: ScheduledAlertsStore(fileURL: fileURL),
        scheduler: scheduler,
        delivery: delivery,
        durableNotificationScheduler: durableScheduler,
        dateProvider: dateProvider
    )

    return Stage1ModalTestContext(
        fileURL: fileURL,
        settings: settings,
        scheduler: scheduler,
        durableScheduler: durableScheduler,
        delivery: delivery,
        engine: engine,
        event: event,
        alertId: event.alertIdentifier(for: .stage1),
        stage1FireTime: eventStart.addingTimeInterval(-10 * 60),
        stage2FireTime: eventStart.addingTimeInterval(-2 * 60)
    )
}

private func fireFirstStage1Handler(_ context: Stage1ModalTestContext) async throws {
    let handler = try #require(await context.scheduler.firstHandler(alertId: context.alertId))
    handler()
    try await Task.sleep(for: .milliseconds(50))
}
