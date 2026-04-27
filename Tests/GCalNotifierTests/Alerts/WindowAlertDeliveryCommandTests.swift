import AppKit
import Foundation
import Testing
import UserNotifications
@testable import GCalNotifier
@testable import GCalNotifierCore

@Suite("WindowAlertDelivery Notification Command Tests")
struct WindowDeliveryCommandTests {
    @MainActor
    @Test("Notification Stage 2 Join opens URL and cleans alert effects")
    func notificationStage2JoinOpensURLAndCleansAlertEffects() async throws {
        var openedURLs: [URL] = []
        let context = try await makeNotificationCommandContext { openedURLs.append($0) }
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        await context.delegate.testHandleResponse(
            alertId: context.alertId,
            categoryIdentifier: NotificationScheduler.stage2AlertCategory,
            actionIdentifier: NotificationScheduler.stage2JoinActionIdentifier
        )

        #expect(openedURLs == [context.joinURL])
        await expectNotificationCommandCleanedUp(context)
    }

    @MainActor
    @Test("Notification Stage 2 Dismiss cleans alert effects without opening URL")
    func notificationStage2DismissCleansAlertEffectsWithoutOpeningURL() async throws {
        var openedURLs: [URL] = []
        let context = try await makeNotificationCommandContext { openedURLs.append($0) }
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        await context.delegate.testHandleResponse(
            alertId: context.alertId,
            categoryIdentifier: NotificationScheduler.stage2AlertCategory,
            actionIdentifier: NotificationScheduler.stage2DismissActionIdentifier
        )

        #expect(openedURLs.isEmpty)
        await expectNotificationCommandCleanedUp(context)
    }

    @MainActor
    @Test("Notification default activation shows context without acknowledging")
    func notificationDefaultActivationShowsContextWithoutAcknowledging() async throws {
        let context = try await makeNotificationCommandContext { _ in }
        defer { cleanupAlertTestTempDir(context.fileURL) }

        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)
        await context.delegate.testHandleResponse(
            alertId: context.alertId,
            categoryIdentifier: NotificationScheduler.stage2AlertCategory,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        #expect(context.windowController.window?.contentView != nil)
        let remaining = await context.engine.scheduledAlerts
        #expect(remaining.contains { $0.id == context.alertId })
        #expect(context.center.removedIdentifiers.isEmpty)
    }
}

private struct NotificationCommandContext {
    let fileURL: URL
    let settings: SettingsStore
    let scheduler: MockAlertScheduler
    let center: MockNotificationCenter
    let delegate: NotificationDelegate
    let windowController: AlertWindowController
    let engine: AlertEngine
    let event: CalendarEvent
    let alertId: String
    let joinURL: URL
}

@MainActor
private func makeNotificationCommandContext(
    urlOpener: @escaping @MainActor @Sendable (URL) -> Void
) async throws -> NotificationCommandContext {
    let fileURL = makeAlertTestTempFileURL()
    let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 5)
    let scheduler = MockAlertScheduler()
    let center = MockNotificationCenter()
    let delegate = NotificationDelegate()
    let notificationScheduler = await NotificationScheduler(center: center, delegate: delegate)
    let windowController = AlertWindowController(window: NSWindow())
    let delivery = WindowAlertDelivery(
        windowController: windowController,
        eventCache: EventCache(fileURL: fileURL),
        settings: settings,
        scheduler: notificationScheduler,
        urlOpener: urlOpener
    )
    let joinURL = try #require(URL(string: "https://meet.google.com/notification-command"))
    let event = makeNotificationCommandEvent(joinURL: joinURL)
    let engine = AlertEngine(
        alertsStore: ScheduledAlertsStore(fileURL: fileURL.appendingPathExtension("alerts")),
        scheduler: scheduler,
        delivery: delivery,
        durableNotificationScheduler: notificationScheduler,
        dateProvider: { event.startTime.addingTimeInterval(-10 * 60) }
    )
    await delivery.setAlertEngine(engine)

    return NotificationCommandContext(
        fileURL: fileURL,
        settings: settings,
        scheduler: scheduler,
        center: center,
        delegate: delegate,
        windowController: windowController,
        engine: engine,
        event: event,
        alertId: event.alertIdentifier(for: .stage2),
        joinURL: joinURL
    )
}

private func makeNotificationCommandEvent(joinURL: URL) -> CalendarEvent {
    makeAlertTestEvent(
        id: "event-1",
        startTime: Date(timeIntervalSince1970: 1_800_500_000),
        meetingLinks: [MeetingLink(url: joinURL)]
    )
}

@MainActor
private func expectNotificationCommandCleanedUp(_ context: NotificationCommandContext) async {
    let remaining = await context.engine.scheduledAlerts
    let cancelledAlerts = await context.scheduler.cancelledAlertIds
    #expect(!remaining.contains { $0.id == context.alertId })
    #expect(cancelledAlerts.contains(context.alertId))
    #expect(context.center.removedIdentifiers.contains(context.alertId))
}
