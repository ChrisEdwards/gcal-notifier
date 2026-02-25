import Foundation
import GCalNotifierCore

/// Alert delivery implementation that shows the alert window.
@MainActor
public final class WindowAlertDelivery: AlertDelivery {
    private let windowController: AlertWindowController
    private let eventCache: EventCache
    private let settings: SettingsStore
    private let scheduler: NotificationScheduler

    /// Alert engine - set after construction to break circular dependency
    private var alertEngine: AlertEngine?

    /// Called when an alert is delivered - use to update UI like status bar
    public var onAlertDelivered: (() -> Void)?

    public init(
        windowController: AlertWindowController,
        eventCache: EventCache,
        settings: SettingsStore,
        scheduler: NotificationScheduler
    ) {
        self.windowController = windowController
        self.eventCache = eventCache
        self.settings = settings
        self.scheduler = scheduler
    }

    /// Sets the alert engine after construction (breaks circular dependency)
    public func setAlertEngine(_ engine: AlertEngine) {
        self.alertEngine = engine
    }

    public nonisolated func deliver(alert: ScheduledAlert) async {
        await MainActor.run {
            self.showAlert(alert, downgraded: false)
        }
    }

    public nonisolated func deliverDowngraded(alert: ScheduledAlert, reason: AlertDowngradeReason) async {
        await self.handleDowngradedAlert(alert, reason: reason)
    }

    @MainActor
    private func showAlert(_ alert: ScheduledAlert, downgraded _: Bool, reason _: AlertDowngradeReason? = nil) {
        // Load the event from cache to get full details
        Task {
            let event = await self.loadEvent(for: alert)
            guard let event else { return }

            let isSnoozed = alert.snoozeCount > 0
            let snoozeContext = isSnoozed ? "Snoozed \(alert.snoozeCount) time(s)" : nil

            if let engine = alertEngine {
                self.windowController.setAlertEngine(engine)
            }
            self.windowController.showAlert(
                for: event,
                stage: alert.stage,
                snoozed: isSnoozed,
                snoozeContext: snoozeContext
            )

            // Play sound
            let soundName = alert.stage == .stage1 ? self.settings.stage1Sound : self.settings.stage2Sound
            SoundPlayer.shared.play(named: soundName, customPath: self.settings.customSoundPath)

            // Notify that alert was delivered (for UI updates like status bar)
            self.onAlertDelivered?()
        }
    }

    @MainActor
    private func handleDowngradedAlert(_ alert: ScheduledAlert, reason: AlertDowngradeReason) async {
        guard let event = await self.loadEvent(for: alert) else { return }

        let title = self.bannerTitle(for: event)
        await self.scheduler.showBannerNotification(
            title: title,
            body: event.title,
            identifier: "\(alert.id)-banner"
        )
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

    private func loadEvent(for alert: ScheduledAlert) async -> CalendarEvent? {
        // Load events from cache and find the matching one
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: alert.eventStartTime)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }

        do {
            let events = try await eventCache.events(from: startOfDay, to: endOfDay)
            return events.first { $0.qualifiedId == alert.eventId }
        } catch {
            return nil
        }
    }
}
