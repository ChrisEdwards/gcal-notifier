import AppKit
import Foundation
import Testing
@testable import GCalNotifier
@testable import GCalNotifierCore

@Suite("WindowAlertDelivery Tests")
struct WindowAlertDeliveryTests {
    @MainActor
    @Test("Deliver uses snapshot fallback when cache is empty")
    func deliverUsesSnapshotFallbackWhenCacheIsEmpty() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let controller = AlertWindowController(window: NSWindow())
        let delivery = try await makeWindowAlertDelivery(
            windowController: controller,
            eventCache: EventCache(fileURL: fileURL)
        )
        let alert = try makeWindowDeliveryStage2Alert()

        await delivery.deliver(alert: alert)

        #expect(controller.window?.contentView != nil)
    }

    @MainActor
    @Test("Deliver prefers cache event over snapshot fallback")
    func deliverPrefersCacheEventOverSnapshotFallback() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let eventCache = EventCache(fileURL: fileURL)
        let alert = try makeWindowDeliveryStage2Alert()
        try await eventCache.save([alert.fallbackCalendarEvent])
        let controller = AlertWindowController(window: NSWindow())
        let delivery = try await makeWindowAlertDelivery(
            windowController: controller,
            eventCache: eventCache
        )

        await delivery.deliver(alert: alert)

        #expect(controller.window?.contentView != nil)
    }

    @MainActor
    @Test("Downgraded delivery does not acknowledge scheduled alert")
    func downgradedDeliveryDoesNotAcknowledgeScheduledAlert() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }

        let alert = try makeWindowDeliveryStage2Alert()
        let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 2)
        let center = MockNotificationCenter()
        let delegate = NotificationDelegate()
        let notificationScheduler = await NotificationScheduler(center: center, delegate: delegate)
        let delivery = WindowAlertDelivery(
            windowController: AlertWindowController(window: NSWindow()),
            eventCache: EventCache(fileURL: fileURL),
            settings: settings,
            scheduler: notificationScheduler
        )
        let engine = AlertEngine(
            alertsStore: ScheduledAlertsStore(fileURL: fileURL.appendingPathExtension("alerts")),
            scheduler: MockAlertScheduler(),
            delivery: delivery,
            durableNotificationScheduler: notificationScheduler,
            dateProvider: { alert.scheduledFireTime.addingTimeInterval(-60) }
        )
        await delivery.setAlertEngine(engine)
        await engine.scheduleAlerts(for: [alert.fallbackCalendarEvent], settings: settings)

        await delivery.deliverDowngraded(alert: alert, reason: .screenSharing)

        let remaining = await engine.scheduledAlerts
        #expect(remaining.contains { $0.id == alert.id })
        #expect(!center.removedIdentifiers.contains(alert.id))
    }
}

@MainActor
private func makeWindowAlertDelivery(
    windowController: AlertWindowController,
    eventCache: EventCache
) async throws -> WindowAlertDelivery {
    let settings = try makeAlertTestSettings()
    let notificationScheduler = await NotificationScheduler(
        center: MockNotificationCenter(),
        delegate: NotificationDelegate()
    )

    return WindowAlertDelivery(
        windowController: windowController,
        eventCache: eventCache,
        settings: settings,
        scheduler: notificationScheduler
    )
}

private func makeWindowDeliveryStage2Alert() throws -> ScheduledAlert {
    let fireTime = Date(timeIntervalSince1970: 1_800_200_000)
    let startTime = fireTime.addingTimeInterval(120)
    let joinURL = try #require(URL(string: "https://meet.google.com/window-fallback"))
    let calendarURL = try #require(URL(string: "https://calendar.google.com/event?eid=window-fallback"))

    return ScheduledAlert(
        id: "cal-1::event-1-stage2",
        eventId: "cal-1::event-1",
        stage: .stage2,
        scheduledFireTime: fireTime,
        eventTitle: "Window Fallback",
        eventStartTime: startTime,
        eventEndTime: startTime.addingTimeInterval(1800),
        joinURL: joinURL,
        calendarURL: calendarURL
    )
}
