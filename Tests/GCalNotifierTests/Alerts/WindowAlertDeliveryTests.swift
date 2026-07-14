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
        #expect(!center.removedPendingIdentifiers.contains(alert.id))
        #expect(!center.removedDeliveredIdentifiers.contains(alert.id))
    }

    @MainActor
    @Test("Overlapping events use distinct alert windows")
    func overlappingEventsUseDistinctAlertWindows() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }
        let settings = try makeAlertTestSettings()
        let context = await makeOverlapDeliveryContext(fileURL: fileURL, settings: settings)
        let first = try makeWindowDeliveryStage2Alert(
            id: "cal-1::event-1-stage2",
            eventId: "cal-1::event-1",
            title: "First overlap"
        )
        let second = try makeWindowDeliveryStage2Alert(
            id: "cal-1::event-2-stage2",
            eventId: "cal-1::event-2",
            title: "Second overlap"
        )

        await context.delivery.deliver(alert: first)
        let firstContentView = context.primaryController.window?.contentView
        await context.delivery.deliver(alert: second)

        #expect(context.primaryController.window?.contentView === firstContentView)
        #expect(context.factory.createdControllers.count == 1)
        #expect(context.factory.createdControllers.first?.window?.contentView != nil)
        #expect(context.primaryController.alertStackIndex == 0)
        #expect(context.factory.createdControllers.first?.alertStackIndex == 1)

        context.primaryController.windowWillClose(
            Notification(name: NSWindow.willCloseNotification, object: context.primaryController.window)
        )
        let third = try makeWindowDeliveryStage2Alert(
            id: "cal-1::event-3-stage2",
            eventId: "cal-1::event-3",
            title: "Third overlap"
        )
        await context.delivery.deliver(alert: third)

        #expect(context.factory.createdControllers.count == 1)
        #expect(context.primaryController.window?.contentView !== firstContentView)
        #expect(context.factory.createdControllers.first?.alertStackIndex == 0)
        #expect(context.primaryController.alertStackIndex == 1)
    }

    @MainActor
    @Test("A later stage replaces the same event's alert window")
    func laterStageReplacesSameEventWindow() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }
        let settings = try makeAlertTestSettings()
        let context = await makeOverlapDeliveryContext(fileURL: fileURL, settings: settings)
        let stage1 = try makeWindowDeliveryStage2Alert(
            id: "cal-1::event-1-stage1",
            stage: .stage1
        )
        let stage2 = try makeWindowDeliveryStage2Alert()

        await context.delivery.deliver(alert: stage1)
        let stage1ContentView = context.primaryController.window?.contentView
        await context.delivery.deliver(alert: stage2)

        #expect(context.primaryController.window?.contentView !== stage1ContentView)
        #expect(context.factory.createdControllers.isEmpty)
    }

    @MainActor
    @Test("Acknowledging one overlapping alert leaves the other active")
    func acknowledgingOneOverlapLeavesOtherActive() async throws {
        let fileURL = makeAlertTestTempFileURL()
        defer { cleanupAlertTestTempDir(fileURL) }
        let settings = try makeAlertTestSettings(stage1Minutes: 0, stage2Minutes: 2)
        let localScheduler = MockAlertScheduler()
        let context = await makeOverlapDeliveryContext(fileURL: fileURL, settings: settings)
        let first = try makeWindowDeliveryStage2Alert(
            id: "cal-1::event-1-stage2",
            eventId: "cal-1::event-1"
        )
        let second = try makeWindowDeliveryStage2Alert(
            id: "cal-1::event-2-stage2",
            eventId: "cal-1::event-2"
        )
        let engine = AlertEngine(
            alertsStore: ScheduledAlertsStore(fileURL: fileURL.appendingPathExtension("alerts")),
            scheduler: localScheduler,
            delivery: context.delivery,
            durableNotificationScheduler: context.notificationScheduler,
            dateProvider: { first.scheduledFireTime.addingTimeInterval(-60) }
        )
        await context.delivery.setAlertEngine(engine)
        await engine.scheduleAlerts(
            for: [first.fallbackCalendarEvent, second.fallbackCalendarEvent],
            settings: settings
        )
        await context.delivery.deliver(alert: first)
        await context.delivery.deliver(alert: second)

        context.primaryController.dismiss()
        for _ in 0 ..< 50 {
            if await !engine.scheduledAlerts.contains(where: { $0.id == first.id }) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let remainingIds = await Set(engine.scheduledAlerts.map(\.id))
        #expect(!remainingIds.contains(first.id))
        #expect(remainingIds.contains(second.id))
    }
}

@MainActor
private final class AlertWindowControllerFactorySpy {
    private(set) var createdControllers: [AlertWindowController] = []

    func makeController() -> AlertWindowController {
        let controller = AlertWindowController(window: NSWindow())
        self.createdControllers.append(controller)
        return controller
    }
}

private struct OverlapDeliveryContext {
    let primaryController: AlertWindowController
    let factory: AlertWindowControllerFactorySpy
    let notificationScheduler: NotificationScheduler
    let delivery: WindowAlertDelivery
}

@MainActor
private func makeOverlapDeliveryContext(
    fileURL: URL,
    settings: SettingsStore
) async -> OverlapDeliveryContext {
    let primaryController = AlertWindowController(window: NSWindow())
    let factory = AlertWindowControllerFactorySpy()
    let notificationScheduler = await NotificationScheduler(
        center: MockNotificationCenter(),
        delegate: NotificationDelegate()
    )
    let delivery = WindowAlertDelivery(
        windowController: primaryController,
        eventCache: EventCache(fileURL: fileURL),
        settings: settings,
        scheduler: notificationScheduler,
        windowControllerFactory: { factory.makeController() }
    )
    return OverlapDeliveryContext(
        primaryController: primaryController,
        factory: factory,
        notificationScheduler: notificationScheduler,
        delivery: delivery
    )
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

private func makeWindowDeliveryStage2Alert(
    id: String = "cal-1::event-1-stage2",
    eventId: String = "cal-1::event-1",
    stage: AlertStage = .stage2,
    title: String = "Window Fallback"
) throws -> ScheduledAlert {
    let fireTime = Date(timeIntervalSince1970: 1_800_200_000)
    let startTime = fireTime.addingTimeInterval(120)
    let joinURL = try #require(URL(string: "https://meet.google.com/window-fallback"))
    let calendarURL = try #require(URL(string: "https://calendar.google.com/event?eid=window-fallback"))

    return ScheduledAlert(
        id: id,
        eventId: eventId,
        stage: stage,
        scheduledFireTime: fireTime,
        eventTitle: title,
        eventStartTime: startTime,
        eventEndTime: startTime.addingTimeInterval(1800),
        joinURL: joinURL,
        calendarURL: calendarURL
    )
}
