import Foundation
import Testing
@testable import GCalNotifierCore

@Suite("AlertEngine Reconcile Snapshot Tests")
struct AlertEngineReconcileSnapshotTests {
    @Test("Changed title updates snapshots and replaces scheduled effects")
    func changedTitleUpdatesSnapshotsAndScheduledEffects() async throws {
        let context = try makeReconcileSnapshotContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        await resetScheduledEffects(context)

        let updatedEvent = makeAlertTestEvent(
            id: context.event.id,
            title: "Updated Meeting",
            startTime: context.event.startTime,
            meetingLinks: context.event.meetingLinks,
            htmlLink: context.event.htmlLink
        )
        await context.engine.reconcile(newEvents: [updatedEvent], settings: context.settings)

        let stage1 = try await persistedAlert(context, stage: .stage1)
        #expect(stage1.eventTitle == "Updated Meeting")
        #expect(stage1.notificationPayload.body.contains("Updated Meeting"))
        await expectReplacedScheduledEffects(context, stage: .stage1)
        await expectDurableNotification(context, stage: .stage1, title: "Updated Meeting")
    }

    @Test("Changed time updates persisted snapshot and trigger")
    func changedTimeUpdatesSnapshotAndTrigger() async throws {
        let context = try makeReconcileSnapshotContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        await resetScheduledEffects(context)

        let updatedStart = context.event.startTime.addingTimeInterval(30 * 60)
        let updatedEnd = updatedStart.addingTimeInterval(90 * 60)
        let updatedEvent = makeAlertTestEvent(
            id: context.event.id,
            title: context.event.title,
            startTime: updatedStart,
            endTime: updatedEnd,
            meetingLinks: context.event.meetingLinks,
            htmlLink: context.event.htmlLink
        )
        await context.engine.reconcile(newEvents: [updatedEvent], settings: context.settings)

        let stage2 = try await persistedAlert(context, stage: .stage2)
        #expect(stage2.eventStartTime == updatedStart)
        #expect(stage2.eventEndTime == updatedEnd)
        #expect(stage2.scheduledFireTime == updatedStart.addingTimeInterval(-2 * 60))
        await expectReplacedScheduledEffects(context, stage: .stage2)
    }

    @Test("Changed join URL updates persisted alert and durable notification")
    func changedJoinURLUpdatesSnapshot() async throws {
        let context = try makeReconcileSnapshotContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        await resetScheduledEffects(context)

        let joinURL = try #require(URL(string: "https://meet.google.com/updated-room"))
        let updatedEvent = makeAlertTestEvent(
            id: context.event.id,
            title: context.event.title,
            startTime: context.event.startTime,
            meetingLinks: [MeetingLink(url: joinURL)],
            htmlLink: context.event.htmlLink
        )
        await context.engine.reconcile(newEvents: [updatedEvent], settings: context.settings)

        let stage1 = try await persistedAlert(context, stage: .stage1)
        #expect(stage1.joinURL == joinURL)
        await expectReplacedScheduledEffects(context, stage: .stage1)
        await expectDurableNotification(context, stage: .stage1, joinURL: joinURL)
    }

    @Test("Changed calendar URL updates persisted alert and durable notification")
    func changedCalendarURLUpdatesSnapshot() async throws {
        let context = try makeReconcileSnapshotContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        await resetScheduledEffects(context)

        let calendarURL = try #require(URL(string: "https://calendar.google.com/event?eid=updated"))
        let updatedEvent = makeAlertTestEvent(
            id: context.event.id,
            title: context.event.title,
            startTime: context.event.startTime,
            meetingLinks: context.event.meetingLinks,
            htmlLink: calendarURL
        )
        await context.engine.reconcile(newEvents: [updatedEvent], settings: context.settings)

        let stage1 = try await persistedAlert(context, stage: .stage1)
        #expect(stage1.calendarURL == calendarURL)
        await expectReplacedScheduledEffects(context, stage: .stage1)
        await expectDurableNotification(context, stage: .stage1, calendarURL: calendarURL)
    }

    @Test("Snoozed alert preserves snooze choice while refreshing snapshot")
    func snoozedAlertPreservesChoiceWhileRefreshingSnapshot() async throws {
        let context = try makeReconcileSnapshotContext(stage1Minutes: 0, stage2Minutes: 5)
        defer { cleanupAlertTestTempDir(context.fileURL) }
        let alertId = context.event.alertIdentifier(for: .stage2)
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        try await context.engine.snooze(alertId: alertId, duration: 60)
        await resetScheduledEffects(context)

        let updatedEvent = makeAlertTestEvent(
            id: context.event.id,
            title: "Updated Snoozed Meeting",
            startTime: context.event.startTime,
            meetingLinks: context.event.meetingLinks,
            htmlLink: context.event.htmlLink
        )
        await context.engine.reconcile(newEvents: [updatedEvent], settings: context.settings)

        let stage2 = try await persistedAlert(context, stage: .stage2)
        #expect(stage2.scheduledFireTime == context.baseTime.addingTimeInterval(60))
        #expect(stage2.originalFireTime == context.event.startTime.addingTimeInterval(-5 * 60))
        #expect(stage2.snoozeCount == 1)
        #expect(stage2.eventTitle == "Updated Snoozed Meeting")
        await expectReplacedScheduledEffects(context, stage: .stage2)
    }
}

private struct ReconcileSnapshotContext {
    let fileURL: URL
    let store: ScheduledAlertsStore
    let scheduler: MockAlertScheduler
    let durableScheduler: MockDurableAlertNotificationScheduler
    let engine: AlertEngine
    let settings: SettingsStore
    let event: CalendarEvent
    let baseTime: Date
}

private func makeReconcileSnapshotContext(
    stage1Minutes: Int = 10,
    stage2Minutes: Int = 2
) throws -> ReconcileSnapshotContext {
    let fileURL = makeAlertTestTempFileURL()
    let store = ScheduledAlertsStore(fileURL: fileURL)
    let scheduler = MockAlertScheduler()
    let durableScheduler = MockDurableAlertNotificationScheduler()
    let baseTime = Date(timeIntervalSince1970: 1_801_000_000)
    let joinURL = try #require(URL(string: "https://meet.google.com/original-room"))
    let calendarURL = try #require(URL(string: "https://calendar.google.com/event?eid=original"))
    let engine = AlertEngine(
        alertsStore: store,
        scheduler: scheduler,
        delivery: MockAlertDelivery(),
        durableNotificationScheduler: durableScheduler,
        dateProvider: { baseTime }
    )
    let event = makeAlertTestEvent(
        id: "event-1",
        title: "Original Meeting",
        startTime: baseTime.addingTimeInterval(60 * 60),
        meetingLinks: [MeetingLink(url: joinURL)],
        htmlLink: calendarURL
    )
    return try ReconcileSnapshotContext(
        fileURL: fileURL,
        store: store,
        scheduler: scheduler,
        durableScheduler: durableScheduler,
        engine: engine,
        settings: makeAlertTestSettings(stage1Minutes: stage1Minutes, stage2Minutes: stage2Minutes),
        event: event,
        baseTime: baseTime
    )
}

private func resetScheduledEffects(_ context: ReconcileSnapshotContext) async {
    await context.scheduler.reset()
    await context.durableScheduler.reset()
}

private func persistedAlert(
    _ context: ReconcileSnapshotContext,
    stage: AlertStage
) async throws -> ScheduledAlert {
    let persisted = try await context.store.load()
    return try #require(persisted.first { $0.stage == stage })
}

private func expectReplacedScheduledEffects(
    _ context: ReconcileSnapshotContext,
    stage: AlertStage
) async {
    let alertId = context.event.alertIdentifier(for: stage)
    #expect(await context.scheduler.cancelledAlertIds.contains(alertId))
    #expect(await context.durableScheduler.cancelledNotificationIds.contains(alertId))
    #expect(await context.scheduler.scheduledAlerts.contains { $0.alertId == alertId })
    #expect(await context.durableScheduler.scheduledNotifications.contains { $0.id == alertId })
}

private func expectDurableNotification(
    _ context: ReconcileSnapshotContext,
    stage: AlertStage,
    title: String? = nil,
    joinURL: URL? = nil,
    calendarURL: URL? = nil
) async {
    let alertId = context.event.alertIdentifier(for: stage)
    let notifications = await context.durableScheduler.scheduledNotifications
    let notification = notifications.last { $0.id == alertId }
    if let title {
        #expect(notification?.eventTitle == title)
    }
    if let joinURL {
        #expect(notification?.joinURL == joinURL)
    }
    if let calendarURL {
        #expect(notification?.calendarURL == calendarURL)
    }
}
