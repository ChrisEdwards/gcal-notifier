import Foundation
import GCalNotifierCore

/// Alert delivery implementation that shows the alert window.
@MainActor
public final class WindowAlertDelivery: AlertDelivery {
    private let windowController: AlertWindowController
    private let eventCache: EventCache
    private let settings: SettingsStore

    /// Alert engine - set after construction to break circular dependency
    private var alertEngine: AlertEngine?

    public init(
        windowController: AlertWindowController,
        eventCache: EventCache,
        settings: SettingsStore
    ) {
        self.windowController = windowController
        self.eventCache = eventCache
        self.settings = settings
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
        // For downgraded alerts, we could show a notification banner instead
        // For now, still show the window but could be modified later
        await MainActor.run {
            self.showAlert(alert, downgraded: true, reason: reason)
        }
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
        }
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
