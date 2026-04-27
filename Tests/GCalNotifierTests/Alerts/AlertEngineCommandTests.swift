import Foundation
import Testing
@testable import GCalNotifierCore

@Suite("AlertEngine Command Tests")
struct AlertEngineCommandTests {
    @Test("Join command acknowledges and cleans Stage 2 effects")
    func joinCommandAcknowledgesAndCleansStage2Effects() async throws {
        let context = try makeCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        let result = await context.engine.handleAlertCommand(.join(alertId: context.alertId))

        expectCommandCompleted(result, alertId: context.alertId)
        await expectAlertCleanedUp(context)
    }

    @Test("Dismiss command acknowledges and cleans Stage 2 effects")
    func dismissCommandAcknowledgesAndCleansStage2Effects() async throws {
        let context = try makeCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        let result = await context.engine.handleAlertCommand(.dismiss(alertId: context.alertId))

        expectCommandCompleted(result, alertId: context.alertId)
        await expectAlertCleanedUp(context)
    }

    @Test("Stage 1 Join acknowledges only Stage 1")
    func stage1JoinAcknowledgesOnlyStage1() async throws {
        let context = try makeStageCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        let result = await context.engine.handleAlertCommand(.join(alertId: context.stage1AlertId))

        expectCommandCompleted(result, alertId: context.stage1AlertId)
        await expectOnlyStage1Completed(context)
    }

    @Test("Stage 1 Dismiss acknowledges only Stage 1")
    func stage1DismissAcknowledgesOnlyStage1() async throws {
        let context = try makeStageCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        let result = await context.engine.handleAlertCommand(.dismiss(alertId: context.stage1AlertId))

        expectCommandCompleted(result, alertId: context.stage1AlertId)
        await expectOnlyStage1Completed(context)
    }

    @Test("Snooze command updates alert state and replaces Stage 2 effects")
    func snoozeCommandUpdatesAlertStateAndReplacesStage2Effects() async throws {
        let context = try makeCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        let result = await context.engine.handleAlertCommand(.snooze(alertId: context.alertId, duration: 60))

        expectCommandSnoozed(result, alertId: context.alertId)
        try await expectAlertSnoozed(context, expectedFireTime: context.now.addingTimeInterval(60))
    }

    @Test("Snooze command rejects meeting start boundary")
    func snoozeCommandRejectsMeetingStartBoundary() async throws {
        let context = try makeCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        let result = await context.engine.handleAlertCommand(.snooze(alertId: context.alertId, duration: 5 * 60))
        let remaining = await context.engine.scheduledAlerts

        #expect(result == .rejected(alertId: context.alertId, error: .snoozePastMeetingStart))
        #expect(remaining.contains { $0.id == context.alertId })
        #expect(await context.scheduler.cancelledAlertIds.isEmpty)
        #expect(await context.durableScheduler.cancelledNotificationIds.isEmpty)
    }

    @Test("Repeated command no-ops after first completion")
    func repeatedCommandNoOpsAfterFirstCompletion() async throws {
        let context = try makeCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        _ = await context.engine.handleAlertCommand(.dismiss(alertId: context.alertId))
        let secondResult = await context.engine.handleAlertCommand(.dismiss(alertId: context.alertId))

        #expect(secondResult == .missingAlert(alertId: context.alertId))
    }

    @Test("Missing alert command no-ops")
    func missingAlertCommandNoOps() async throws {
        let context = try makeCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        let result = await context.engine.handleAlertCommand(.join(alertId: context.alertId))

        #expect(result == .missingAlert(alertId: context.alertId))
        #expect(await context.scheduler.cancelledAlertIds.isEmpty)
        #expect(await context.durableScheduler.cancelledNotificationIds.isEmpty)
    }

    @Test("Default activation presents context without acknowledging")
    func defaultActivationPresentsContextWithoutAcknowledging() async throws {
        let context = try makeCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        let result = await context.engine.handleAlertCommand(.showContext(alertId: context.alertId))

        expectCommandPresented(result, alertId: context.alertId)
        #expect(await context.delivery.deliveredAlerts.map(\.id) == [context.alertId])
        let remaining = await context.engine.scheduledAlerts
        #expect(remaining.contains { $0.id == context.alertId })
        #expect(await context.durableScheduler.cancelledNotificationIds.isEmpty)
    }
}

private struct CommandContext {
    let fileURL: URL
    let store: ScheduledAlertsStore
    let settings: SettingsStore
    let scheduler: MockAlertScheduler
    let durableScheduler: MockDurableAlertNotificationScheduler
    let delivery: MockAlertDelivery
    let engine: AlertEngine
    let event: CalendarEvent
    let now: Date
    let alertId: String
}

private struct StageCommandContext {
    let fileURL: URL
    let settings: SettingsStore
    let scheduler: MockAlertScheduler
    let durableScheduler: MockDurableAlertNotificationScheduler
    let engine: AlertEngine
    let event: CalendarEvent
    let stage1AlertId: String
    let stage2AlertId: String
}

private func makeCommandContext() throws -> CommandContext {
    let fileURL = makeAlertTestTempFileURL()
    let store = ScheduledAlertsStore(fileURL: fileURL)
    let scheduler = MockAlertScheduler()
    let durableScheduler = MockDurableAlertNotificationScheduler()
    let delivery = MockAlertDelivery()
    let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 5)
    let eventStart = Date(timeIntervalSince1970: 1_800_300_000)
    let now = eventStart.addingTimeInterval(-5 * 60)
    let event = makeAlertTestEvent(id: "event-1", startTime: eventStart)
    let engine = AlertEngine(
        alertsStore: store,
        scheduler: scheduler,
        delivery: delivery,
        durableNotificationScheduler: durableScheduler,
        dateProvider: { now }
    )

    return CommandContext(
        fileURL: fileURL,
        store: store,
        settings: settings,
        scheduler: scheduler,
        durableScheduler: durableScheduler,
        delivery: delivery,
        engine: engine,
        event: event,
        now: now,
        alertId: event.alertIdentifier(for: .stage2)
    )
}

private func makeStageCommandContext() throws -> StageCommandContext {
    let fileURL = makeAlertTestTempFileURL()
    let scheduler = MockAlertScheduler()
    let durableScheduler = MockDurableAlertNotificationScheduler()
    let delivery = MockAlertDelivery()
    let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 2)
    let now = Date(timeIntervalSince1970: 1_800_700_000)
    let event = makeAlertTestEvent(id: "event-1", startTime: now.addingTimeInterval(30 * 60))
    let engine = AlertEngine(
        alertsStore: ScheduledAlertsStore(fileURL: fileURL),
        scheduler: scheduler,
        delivery: delivery,
        durableNotificationScheduler: durableScheduler,
        dateProvider: { now }
    )

    return StageCommandContext(
        fileURL: fileURL,
        settings: settings,
        scheduler: scheduler,
        durableScheduler: durableScheduler,
        engine: engine,
        event: event,
        stage1AlertId: event.alertIdentifier(for: .stage1),
        stage2AlertId: event.alertIdentifier(for: .stage2)
    )
}

private func expectCommandCompleted(_ result: AlertCommandResult, alertId: String) {
    guard case let .completed(alert) = result else {
        Issue.record("Expected completed command result")
        return
    }
    #expect(alert.id == alertId)
}

private func expectCommandSnoozed(_ result: AlertCommandResult, alertId: String) {
    guard case let .snoozed(alert) = result else {
        Issue.record("Expected snoozed command result")
        return
    }
    #expect(alert.id == alertId)
}

private func expectCommandPresented(_ result: AlertCommandResult, alertId: String) {
    guard case let .presented(alert) = result else {
        Issue.record("Expected presented command result")
        return
    }
    #expect(alert.id == alertId)
}

private func expectAlertCleanedUp(_ context: CommandContext) async {
    let remaining = await context.engine.scheduledAlerts
    let cancelledAlerts = await context.scheduler.cancelledAlertIds
    let cancelledNotifications = await context.durableScheduler.cancelledNotificationIds
    let acknowledged = await context.engine.acknowledgedAlerts
    #expect(!remaining.contains { $0.id == context.alertId })
    #expect(cancelledAlerts.contains(context.alertId))
    #expect(cancelledNotifications.contains(context.alertId))
    #expect(acknowledged.contains(context.alertId))
}

private func expectAlertSnoozed(_ context: CommandContext, expectedFireTime: Date) async throws {
    let alerts = await context.engine.scheduledAlerts
    let scheduledAlerts = await context.scheduler.scheduledAlerts
    let scheduledNotifications = await context.durableScheduler.scheduledNotifications
    let cancelledAlerts = await context.scheduler.cancelledAlertIds
    let cancelledNotifications = await context.durableScheduler.cancelledNotificationIds
    let snoozedAlert = try #require(alerts.first { $0.id == context.alertId })
    let persisted = try await context.store.load()
    let persistedAlert = persisted.first { $0.id == context.alertId }
    #expect(snoozedAlert.scheduledFireTime == expectedFireTime)
    #expect(snoozedAlert.snoozeCount == 1)
    #expect(snoozedAlert.originalFireTime == context.now)
    #expect(persistedAlert?.scheduledFireTime == expectedFireTime)
    #expect(cancelledAlerts.contains(context.alertId))
    #expect(cancelledNotifications.contains(context.alertId))
    #expect(scheduledAlerts.last?.fireDate == expectedFireTime)
    #expect(scheduledNotifications.last?.scheduledFireTime == expectedFireTime)
}

private func expectOnlyStage1Completed(_ context: StageCommandContext) async {
    let remaining = await context.engine.scheduledAlerts
    let acknowledged = await context.engine.acknowledgedAlerts
    let cancelledAlerts = await context.scheduler.cancelledAlertIds
    let cancelledNotifications = await context.durableScheduler.cancelledNotificationIds
    #expect(!remaining.contains { $0.id == context.stage1AlertId })
    #expect(remaining.contains { $0.id == context.stage2AlertId })
    #expect(acknowledged.contains(context.stage1AlertId))
    #expect(!acknowledged.contains(context.stage2AlertId))
    #expect(cancelledAlerts.contains(context.stage1AlertId))
    #expect(cancelledNotifications.contains(context.stage1AlertId))
    #expect(!cancelledAlerts.contains(context.stage2AlertId))
    #expect(!cancelledNotifications.contains(context.stage2AlertId))
}
