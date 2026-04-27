import AppKit
import Foundation
import GCalNotifierCore
import OSLog

/// Alert delivery implementation that shows the alert window.
@MainActor
public final class WindowAlertDelivery: AlertDelivery {
    private let windowController: AlertWindowController
    private let eventCache: EventCache
    private let settings: SettingsStore
    private let scheduler: NotificationScheduler
    private let urlOpener: @MainActor @Sendable (URL) -> Void

    /// Alert engine - set after construction to break circular dependency
    private var alertEngine: AlertEngine?

    /// Called when an alert is delivered - use to update UI like status bar
    public var onAlertDelivered: (() -> Void)?

    public init(
        windowController: AlertWindowController,
        eventCache: EventCache,
        settings: SettingsStore,
        scheduler: NotificationScheduler,
        urlOpener: @escaping @MainActor @Sendable (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        }
    ) {
        self.windowController = windowController
        self.eventCache = eventCache
        self.settings = settings
        self.scheduler = scheduler
        self.urlOpener = urlOpener
    }

    /// Sets the alert engine after construction (breaks circular dependency)
    public func setAlertEngine(_ engine: AlertEngine) async {
        self.alertEngine = engine
        await self.scheduler.setAlertCommandHandler { [weak self, weak engine] command in
            guard let engine else { return }
            let result = await engine.handleAlertCommand(command)
            await self?.completeNotificationCommand(command, result: result)
        }
    }

    public nonisolated func deliver(alert: ScheduledAlert) async {
        await self.showAlert(alert)
    }

    public nonisolated func deliverDowngraded(alert: ScheduledAlert, reason: AlertDowngradeReason) async {
        await self.handleDowngradedAlert(alert, reason: reason)
    }

    @MainActor
    private func showAlert(_ alert: ScheduledAlert) async {
        let event = await self.displayEvent(for: alert)
        let isSnoozed = alert.snoozeCount > 0
        let snoozeContext = isSnoozed ? "Snoozed \(alert.snoozeCount) time(s)" : nil
        let snoozeDurations = await self.snoozeDurations(for: alert)

        if let engine = alertEngine {
            self.windowController.setAlertEngine(engine)
        }
        self.windowController.showAlert(
            for: event,
            stage: alert.stage,
            snoozed: isSnoozed,
            snoozeContext: snoozeContext,
            snoozeDurations: snoozeDurations
        )
        Logger.alerts.info(
            "Alert window shown for \(alert.id) (stage=\(alert.stage.rawValue), snoozed=\(isSnoozed))"
        )

        let soundName = alert.stage == .stage1 ? self.settings.stage1Sound : self.settings.stage2Sound
        SoundPlayer.shared.play(named: soundName, customPath: self.settings.customSoundPath)
        self.onAlertDelivered?()
    }

    @MainActor
    private func handleDowngradedAlert(_ alert: ScheduledAlert, reason: AlertDowngradeReason) async {
        let event = await self.displayEvent(for: alert)
        let title = self.bannerTitle(for: event)
        await self.scheduler.showBannerNotification(
            title: title,
            body: event.title,
            identifier: "\(alert.id)-banner"
        )
        Logger.alerts.info("Banner shown for \(alert.id) (reason=\(String(describing: reason)))")
        SoundPlayer.shared.playDowngradedAlertSound(for: reason)
        self.onAlertDelivered?()
        if let engine = self.alertEngine {
            await engine.acknowledgeAlert(alertId: alert.id, eventStartTime: alert.eventStartTime)
        }
    }

    private func bannerTitle(for event: CalendarEvent) -> String {
        let timeUntil = event.startTime.timeIntervalSinceNow

        if timeUntil <= 0 {
            return "Meeting started!"
        }
        if timeUntil < 60 {
            return "Meeting starts now"
        }
        let minutes = Int(timeUntil / 60)
        return "Meeting in \(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    private func displayEvent(for alert: ScheduledAlert) async -> CalendarEvent {
        if let event = await self.loadEvent(for: alert) {
            return event
        }

        Logger.alerts.warning(
            "Using alert snapshot fallback for \(alert.id) (stage=\(alert.stage.rawValue))"
        )
        return alert.fallbackCalendarEvent
    }

    private func snoozeDurations(for alert: ScheduledAlert) async -> [TimeInterval] {
        guard let engine = self.alertEngine else { return AlertSnoozePolicy.supportedDurations }
        return await engine.validSnoozeDurations(alertId: alert.id)
    }

    @MainActor
    private func completeNotificationCommand(_ command: AlertCommand, result: AlertCommandResult) {
        guard case .join = command,
              case let .completed(alert) = result,
              let joinURL = alert.joinURL
        else { return }
        self.urlOpener(joinURL)
    }

    private func loadEvent(for alert: ScheduledAlert) async -> CalendarEvent? {
        // Load events from cache and find the matching one
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: alert.eventStartTime)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }

        do {
            let events = try await eventCache.events(from: startOfDay, to: endOfDay)
            return events.first { $0.qualifiedId == alert.eventId }
        } catch {
            Logger.alerts.error(
                "Event cache load failed during alert delivery for \(alert.id): \(error.localizedDescription)"
            )
            return nil
        }
    }
}
