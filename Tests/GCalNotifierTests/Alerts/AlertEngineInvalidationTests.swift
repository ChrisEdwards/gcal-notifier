import Foundation
import Testing
@testable import GCalNotifierCore

@Suite("AlertEngine Invalidation Tests")
struct AlertEngineInvalidationTests {
    @Test("Declined event invalidates alerts and scheduled effects")
    func declinedEventInvalidatesAlerts() async throws {
        let context = try makeInvalidationContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)

        let declined = makeInvalidationEvent(context, responseStatus: .declined)
        await context.engine.reconcile(newEvents: [declined], settings: context.settings)

        try await expectInvalidated(context)
    }

    @Test("All-day event invalidates alerts and scheduled effects")
    func allDayEventInvalidatesAlerts() async throws {
        let context = try makeInvalidationContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)

        let allDay = makeInvalidationEvent(context, isAllDay: true)
        await context.engine.reconcile(newEvents: [allDay], settings: context.settings)

        try await expectInvalidated(context)
    }

    @Test("Deleted event invalidates alerts and scheduled effects")
    func deletedEventInvalidatesAlerts() async throws {
        let context = try makeInvalidationContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)

        await context.engine.reconcile(newEvents: [], settings: context.settings)

        try await expectInvalidated(context)
    }

    @Test("Canceled event omitted by sync invalidates alerts and scheduled effects")
    func canceledEventInvalidatesAlerts() async throws {
        let context = try makeInvalidationContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)

        await context.engine.reconcile(newEvents: [], settings: context.settings)

        try await expectInvalidated(context)
    }

    @Test("Event without meeting link invalidates alerts and scheduled effects")
    func noLongerAlertableEventInvalidatesAlerts() async throws {
        let context = try makeInvalidationContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)

        let noMeetingLink = makeInvalidationEvent(context, meetingLinks: [])
        await context.engine.reconcile(newEvents: [noMeetingLink], settings: context.settings)

        try await expectInvalidated(context)
    }

    @Test("Blocked keyword invalidates alerts and scheduled effects")
    func blockedKeywordInvalidatesAlerts() async throws {
        let context = try makeInvalidationContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)

        context.settings.blockedKeywords = ["blocked"]
        let blocked = makeInvalidationEvent(context, title: "Blocked planning")
        await context.engine.reconcile(newEvents: [blocked], settings: context.settings)

        try await expectInvalidated(context)
    }

    @Test("Disabled calendar invalidates alerts and scheduled effects")
    func disabledCalendarInvalidatesAlerts() async throws {
        let context = try makeInvalidationContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)

        context.settings.enabledCalendars = ["other-calendar"]
        await context.engine.reconcile(newEvents: [context.event], settings: context.settings)

        try await expectInvalidated(context)
    }

    @Test("Invalidated local trigger cannot present stale modal")
    func invalidatedLocalTriggerCannotPresentStaleModal() async throws {
        let context = try makeInvalidationContext()
        defer { cleanupAlertTestTempDir(context.fileURL) }
        let alertId = context.event.alertIdentifier(for: .stage1)
        await context.engine.scheduleAlerts(for: [context.event], settings: context.settings)

        await context.engine.reconcile(newEvents: [], settings: context.settings)
        await context.scheduler.fireAlert(alertId: alertId)
        try await Task.sleep(for: .milliseconds(50))

        #expect(await context.delivery.deliveredAlerts.isEmpty)
    }

    @Test("Force-alert keyword setting makes cached event eligible")
    func forceAlertKeywordMakesCachedEventEligible() async throws {
        let context = try makeInvalidationContext(meetingLinks: [])
        defer { cleanupAlertTestTempDir(context.fileURL) }
        let cachedEvent = makeInvalidationEvent(context, title: "Candidate screen", meetingLinks: [])
        await context.engine.scheduleAlerts(for: [cachedEvent], settings: context.settings)
        #expect(await context.engine.scheduledAlerts.isEmpty)

        context.settings.forceAlertKeywords = ["screen"]
        await context.engine.reconcile(newEvents: [cachedEvent], settings: context.settings)

        let alerts = await context.engine.scheduledAlerts
        let persisted = try await context.store.load()
        let scheduledIds = await context.scheduler.scheduledAlerts.map(\.alertId)
        #expect(Set(alerts.map(\.id)) == expectedAlertIds(for: cachedEvent))
        #expect(Set(persisted.map(\.id)) == expectedAlertIds(for: cachedEvent))
        #expect(Set(scheduledIds) == expectedAlertIds(for: cachedEvent))
        #expect(await context.durableScheduler.scheduledNotifications.count == 2)
    }
}

private struct InvalidationContext {
    let fileURL: URL
    let store: ScheduledAlertsStore
    let scheduler: MockAlertScheduler
    let durableScheduler: MockDurableAlertNotificationScheduler
    let delivery: MockAlertDelivery
    let engine: AlertEngine
    let settings: SettingsStore
    let event: CalendarEvent
}

private func makeInvalidationContext(meetingLinks: [MeetingLink]? = nil) throws -> InvalidationContext {
    let fileURL = makeAlertTestTempFileURL()
    let store = ScheduledAlertsStore(fileURL: fileURL)
    let scheduler = MockAlertScheduler()
    let durableScheduler = MockDurableAlertNotificationScheduler()
    let delivery = MockAlertDelivery()
    let baseTime = Date(timeIntervalSince1970: 1_801_100_000)
    let settings = try makeAlertTestSettings(stage1Minutes: 10, stage2Minutes: 2)
    let engine = AlertEngine(
        alertsStore: store,
        scheduler: scheduler,
        delivery: delivery,
        durableNotificationScheduler: durableScheduler,
        dateProvider: { baseTime }
    )
    let event = makeAlertTestEvent(
        id: "event-1",
        calendarId: "cal-1",
        title: "Planning",
        startTime: baseTime.addingTimeInterval(60 * 60),
        meetingLinks: meetingLinks
    )
    return InvalidationContext(
        fileURL: fileURL,
        store: store,
        scheduler: scheduler,
        durableScheduler: durableScheduler,
        delivery: delivery,
        engine: engine,
        settings: settings,
        event: event
    )
}

private func makeInvalidationEvent(
    _ context: InvalidationContext,
    title: String? = nil,
    isAllDay: Bool? = nil,
    meetingLinks: [MeetingLink]? = nil,
    responseStatus: ResponseStatus? = nil
) -> CalendarEvent {
    makeAlertTestEvent(
        id: context.event.id,
        calendarId: context.event.calendarId,
        title: title ?? context.event.title,
        startTime: context.event.startTime,
        endTime: context.event.endTime,
        isAllDay: isAllDay ?? context.event.isAllDay,
        meetingLinks: meetingLinks ?? context.event.meetingLinks,
        responseStatus: responseStatus ?? context.event.responseStatus,
        htmlLink: context.event.htmlLink
    )
}

private func expectInvalidated(_ context: InvalidationContext) async throws {
    let alertIds = expectedAlertIds(for: context.event)
    let alerts = await context.engine.scheduledAlerts
    let persisted = try await context.store.load()
    let cancelledTriggers = await context.scheduler.cancelledAlertIds
    let cancelledPending = await context.durableScheduler.cancelledPendingNotificationIds
    let removedDelivered = await context.durableScheduler.removedDeliveredNotificationIds
    #expect(alerts.allSatisfy { !alertIds.contains($0.id) })
    #expect(persisted.allSatisfy { !alertIds.contains($0.id) })
    #expect(alertIds.isSubset(of: Set(cancelledTriggers)))
    #expect(alertIds.isSubset(of: Set(cancelledPending)))
    #expect(alertIds.isSubset(of: Set(removedDelivered)))
    #expect(await context.durableScheduler.scheduledNotifications.isEmpty)
}

private func expectedAlertIds(for event: CalendarEvent) -> Set<String> {
    Set(AlertStage.allCases.map { event.alertIdentifier(for: $0) })
}
