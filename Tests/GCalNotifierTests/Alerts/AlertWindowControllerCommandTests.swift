import AppKit
import Foundation
import Testing
@testable import GCalNotifier
@testable import GCalNotifierCore

@MainActor
private final class NonNotifyingPanel: NSPanel {
    override func close() {}
}

@Suite("AlertWindowController Command Tests")
struct AlertWindowControllerCommandTests {
    @MainActor
    @Test("Modal Stage 2 Join opens URL and cleans alert effects")
    func modalStage2JoinOpensURLAndCleansAlertEffects() async throws {
        let context = try makeModalCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        var openedURLs: [URL] = []

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        context.controller.setAlertEngine(context.engine)
        context.controller.setURLOpener { openedURLs.append($0) }
        context.controller.showAlert(for: context.event, stage: .stage2)

        context.controller.joinMeeting()
        try await Task.sleep(for: .milliseconds(50))

        #expect(openedURLs == [context.joinURL])
        try await expectModalCommandCleanedUp(context)
    }

    @MainActor
    @Test("Modal Stage 2 Dismiss cleans alert effects without opening URL")
    func modalStage2DismissCleansAlertEffectsWithoutOpeningURL() async throws {
        let context = try makeModalCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        var openedURLs: [URL] = []

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        context.controller.setAlertEngine(context.engine)
        context.controller.setURLOpener { openedURLs.append($0) }
        context.controller.showAlert(for: context.event, stage: .stage2)

        context.controller.dismiss()
        try await Task.sleep(for: .milliseconds(50))

        #expect(openedURLs.isEmpty)
        try await expectModalCommandCleanedUp(context)
    }

    @MainActor
    @Test("Modal close acknowledges alert without removing delivered OS notification")
    func modalCloseAcknowledgesWithoutRemovingDeliveredOSNotification() async throws {
        let context = try makeModalCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        context.controller.setAlertEngine(context.engine)
        context.controller.showAlert(for: context.event, stage: .stage2)

        let notification = Notification(
            name: NSWindow.willCloseNotification,
            object: context.controller.window
        )
        context.controller.windowWillClose(notification)

        try await expectModalCommandCleanedUp(context)
    }

    @MainActor
    @Test("Modal Stage 2 Snooze updates state and replaces alert effects")
    func modalStage2SnoozeUpdatesStateAndReplacesAlertEffects() async throws {
        let context = try makeModalCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        context.controller.setAlertEngine(context.engine)
        context.controller.showAlert(for: context.event, stage: .stage2)

        context.controller.snoozeMeeting(duration: 60)

        try await expectModalAlertSnoozed(context, expectedFireTime: context.now.addingTimeInterval(60))
    }

    @MainActor
    @Test("Expired modal closes without acknowledging the alert")
    func expiredModalClosesWithoutAcknowledgingAlert() async throws {
        let context = try makeModalCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        let controller = AlertWindowController(window: NonNotifyingPanel())
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        controller.setAlertEngine(context.engine)
        controller.showAlert(for: context.event, stage: .stage2)

        controller.maintainAlertVisibility(at: context.event.startTime.addingTimeInterval(5 * 60))
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: controller.window))
        for _ in 0 ..< 50 {
            if await !context.engine.scheduledAlerts.contains(where: { $0.id == context.alertId }) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(await context.engine.scheduledAlerts.contains { $0.id == context.alertId })
    }

    @MainActor
    @Test("Escape does not acknowledge or close the alert")
    func escapeDoesNotAcknowledgeOrCloseAlert() async throws {
        let context = try makeModalCommandContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        context.controller.setAlertEngine(context.engine)
        context.controller.showAlert(for: context.event, stage: .stage2)

        context.controller.cancelOperation(nil)
        for _ in 0 ..< 50 {
            if await !context.engine.scheduledAlerts.contains(where: { $0.id == context.alertId }) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(await context.engine.scheduledAlerts.contains { $0.id == context.alertId })
    }
}

private struct ModalCommandContext {
    let fileURL: URL
    let settings: SettingsStore
    let scheduler: MockAlertScheduler
    let durableScheduler: MockDurableAlertNotificationScheduler
    let engine: AlertEngine
    let event: CalendarEvent
    let controller: AlertWindowController
    let now: Date
    let alertId: String
    let joinURL: URL
}

@MainActor
private func makeModalCommandContext() throws -> ModalCommandContext {
    let fileURL = makeAlertTestTempFileURL()
    let store = ScheduledAlertsStore(fileURL: fileURL)
    let scheduler = MockAlertScheduler()
    let durableScheduler = MockDurableAlertNotificationScheduler()
    let delivery = MockAlertDelivery()
    let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 5)
    let joinURL = try #require(URL(string: "https://meet.google.com/modal-command"))
    let eventStart = Date(timeIntervalSince1970: 1_800_400_000)
    let event = makeAlertTestEvent(
        id: "event-1",
        startTime: eventStart,
        meetingLinks: [MeetingLink(url: joinURL)]
    )
    let engine = AlertEngine(
        alertsStore: store,
        scheduler: scheduler,
        delivery: delivery,
        durableNotificationScheduler: durableScheduler,
        dateProvider: { eventStart.addingTimeInterval(-5 * 60) }
    )
    let now = eventStart.addingTimeInterval(-5 * 60)

    return ModalCommandContext(
        fileURL: fileURL,
        settings: settings,
        scheduler: scheduler,
        durableScheduler: durableScheduler,
        engine: engine,
        event: event,
        controller: AlertWindowController(window: NSWindow()),
        now: now,
        alertId: event.alertIdentifier(for: .stage2),
        joinURL: joinURL
    )
}

@MainActor
private func expectModalCommandCleanedUp(_ context: ModalCommandContext) async throws {
    for _ in 0 ..< 50 {
        let remaining = await context.engine.scheduledAlerts
        if !remaining.contains(where: { $0.id == context.alertId }) {
            break
        }
        try await Task.sleep(for: .milliseconds(10))
    }

    let remaining = await context.engine.scheduledAlerts
    let cancelledAlerts = await context.scheduler.cancelledAlertIds
    let cancelledNotifications = await context.durableScheduler.cancelledNotificationIds
    let removedDeliveredNotifications = await context.durableScheduler.removedDeliveredNotificationIds
    #expect(!remaining.contains { $0.id == context.alertId })
    #expect(cancelledAlerts.contains(context.alertId))
    #expect(cancelledNotifications.contains(context.alertId))
    #expect(removedDeliveredNotifications.isEmpty)
}

@MainActor
private func expectModalAlertSnoozed(_ context: ModalCommandContext, expectedFireTime: Date) async throws {
    for _ in 0 ..< 50 {
        let alerts = await context.engine.scheduledAlerts
        if alerts.first(where: { $0.id == context.alertId })?.scheduledFireTime == expectedFireTime {
            break
        }
        try await Task.sleep(for: .milliseconds(10))
    }

    let alerts = await context.engine.scheduledAlerts
    let alert = try #require(alerts.first { $0.id == context.alertId })
    let cancelledAlerts = await context.scheduler.cancelledAlertIds
    let cancelledNotifications = await context.durableScheduler.cancelledNotificationIds
    let removedDeliveredNotifications = await context.durableScheduler.removedDeliveredNotificationIds
    #expect(alert.scheduledFireTime == expectedFireTime)
    #expect(alert.snoozeCount == 1)
    #expect(alert.originalFireTime == context.now)
    #expect(cancelledAlerts.contains(context.alertId))
    #expect(cancelledNotifications.contains(context.alertId))
    #expect(removedDeliveredNotifications.isEmpty)
}
