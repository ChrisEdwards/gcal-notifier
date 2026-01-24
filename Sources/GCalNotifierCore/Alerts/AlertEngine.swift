import Foundation

/// Protocol for scheduling and canceling timer-based alert delivery.
/// Abstracted to allow testing with mocks.
public protocol AlertScheduler: Sendable {
    func schedule(alertId: String, fireDate: Date, handler: @escaping @Sendable () -> Void) async
    func cancel(alertId: String) async
    func cancelAll() async
}

/// Default alert scheduler using DispatchSourceTimer.
public actor DispatchAlertScheduler: AlertScheduler {
    private var timers: [String: DispatchSourceTimer] = [:]

    public init() {}

    public func schedule(alertId: String, fireDate: Date, handler: @escaping @Sendable () -> Void) {
        self.cancel(alertId: alertId)

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        let interval = max(0, fireDate.timeIntervalSinceNow)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { handler() }
        timer.resume()
        self.timers[alertId] = timer
    }

    public func cancel(alertId: String) {
        if let timer = timers.removeValue(forKey: alertId) {
            timer.cancel()
        }
    }

    public func cancelAll() {
        for (_, timer) in self.timers {
            timer.cancel()
        }
        self.timers.removeAll()
    }
}

/// Protocol for delivering alerts when they fire.
/// Abstracted to allow testing with mocks.
public protocol AlertDelivery: Sendable {
    func deliver(alert: ScheduledAlert) async
    func deliverDowngraded(alert: ScheduledAlert, reason: AlertDowngradeReason) async
}

// MARK: - Alert Downgrade Reason

/// Reason why an alert was downgraded from modal to notification banner.
public enum AlertDowngradeReason: Sendable, Equatable {
    /// User is currently in another meeting (back-to-back situation).
    case backToBackMeeting
    /// User is currently sharing their screen.
    case screenSharing
    /// Do Not Disturb is enabled.
    case doNotDisturb
}

// MARK: - Back-to-Back Alert Context

/// Context for back-to-back alert handling.
public struct BackToBackAlertContext: Sendable, Equatable {
    /// Whether the user is currently in a meeting.
    public let isInMeeting: Bool

    /// Whether this alert is for a back-to-back meeting.
    public let isBackToBackSituation: Bool

    /// The current meeting the user is in (if any).
    public let currentMeeting: CalendarEvent?

    public init(isInMeeting: Bool, isBackToBackSituation: Bool, currentMeeting: CalendarEvent?) {
        self.isInMeeting = isInMeeting
        self.isBackToBackSituation = isBackToBackSituation
        self.currentMeeting = currentMeeting
    }

    /// No back-to-back context (user not in a meeting).
    public static let none = BackToBackAlertContext(
        isInMeeting: false,
        isBackToBackSituation: false,
        currentMeeting: nil
    )
}

// MARK: - MissedAlertResult

/// Result of checking for a missed alert after wake from sleep.
public enum MissedAlertResult: Sendable, Equatable {
    /// The meeting hasn't started yet - fire alert immediately.
    case fireNow(ScheduledAlert)

    /// The meeting just started (within grace period) - show "Meeting started!" alert.
    case meetingJustStarted(ScheduledAlert)

    /// The meeting is too old to alert (started more than 5 minutes ago).
    case tooOld(ScheduledAlert)
}

// MARK: - Alert Errors

/// Errors that can occur during alert operations.
public enum AlertError: Error, Equatable, Sendable {
    /// Cannot snooze - the meeting has already started.
    case meetingAlreadyStarted

    /// Cannot snooze - the snooze duration would exceed the meeting start time.
    case snoozePastMeetingStart

    /// The specified alert was not found.
    case alertNotFound(alertId: String)
}

extension AlertError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .meetingAlreadyStarted:
            "The meeting has already started."
        case .snoozePastMeetingStart:
            "Cannot snooze past the meeting start time."
        case let .alertNotFound(alertId):
            "Alert not found: \(alertId)"
        }
    }
}

/// Central alert scheduling and state management.
/// Handles two-stage alerts with persistence and recovery support.
public actor AlertEngine {
    // MARK: - Dependencies

    private let alertsStore: ScheduledAlertsStore
    private let scheduler: AlertScheduler
    private let delivery: AlertDelivery
    private let dateProvider: @Sendable () -> Date

    // MARK: - State

    private var alerts: [String: ScheduledAlert] = [:]
    private var acknowledgedEventIds: Set<String> = []
    private var isInitialized = false

    /// Provider for back-to-back context. Set this to enable back-to-back detection during alerts.
    private var backToBackContextProvider: (@Sendable (ScheduledAlert) async -> BackToBackAlertContext)?

    // MARK: - Public Access

    /// Currently scheduled alerts.
    public var scheduledAlerts: [ScheduledAlert] {
        Array(self.alerts.values)
    }

    /// Event IDs that have been acknowledged.
    public var acknowledgedEvents: Set<String> {
        self.acknowledgedEventIds
    }

    // MARK: - Initialization

    /// Creates an AlertEngine with the default dependencies.
    public init(alertsStore: ScheduledAlertsStore) async {
        self.alertsStore = alertsStore
        self.scheduler = await DispatchAlertScheduler()
        self.delivery = NoOpAlertDelivery()
        self.dateProvider = { Date() }
    }

    /// Creates an AlertEngine with custom dependencies (for testing).
    public init(
        alertsStore: ScheduledAlertsStore,
        scheduler: AlertScheduler,
        delivery: AlertDelivery,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.alertsStore = alertsStore
        self.scheduler = scheduler
        self.delivery = delivery
        self.dateProvider = dateProvider
    }

    // MARK: - Core Operations

    /// Schedules alerts for the given events based on user settings.
    /// Creates stage 1 (early warning) and stage 2 (urgent reminder) alerts.
    public func scheduleAlerts(for events: [CalendarEvent], settings: SettingsStore) async {
        let now = self.dateProvider()
        let stage1Minutes = settings.alertStage1Minutes
        let stage2Minutes = settings.alertStage2Minutes

        for event in events {
            guard event.shouldAlert else { continue }
            guard !self.acknowledgedEventIds.contains(event.id) else { continue }

            // Schedule Stage 1 if enabled and not in the past
            if stage1Minutes > 0 {
                let stage1Fire = event.startTime.addingTimeInterval(-Double(stage1Minutes * 60))
                if stage1Fire > now {
                    let alert = self.createAlert(for: event, stage: .stage1, fireTime: stage1Fire)
                    await self.scheduleAlert(alert)
                }
            }

            // Schedule Stage 2 if enabled and not in the past
            if stage2Minutes > 0 {
                let stage2Fire = event.startTime.addingTimeInterval(-Double(stage2Minutes * 60))
                if stage2Fire > now {
                    let alert = self.createAlert(for: event, stage: .stage2, fireTime: stage2Fire)
                    await self.scheduleAlert(alert)
                }
            }
        }

        await self.persistAlerts()
    }

    /// Cancels all alerts for the given event.
    public func cancelAlerts(for eventId: String) async {
        let alertsToCancel = self.alerts.values.filter { $0.eventId == eventId }
        for alert in alertsToCancel {
            await self.scheduler.cancel(alertId: alert.id)
            self.alerts.removeValue(forKey: alert.id)
        }
        await self.persistAlerts()
    }

    /// Marks an event as acknowledged, preventing future alerts for it.
    public func acknowledgeAlert(eventId: String) async {
        self.acknowledgedEventIds.insert(eventId)
        await self.cancelAlerts(for: eventId)
    }

    /// Snoozes an alert by the specified duration.
    ///
    /// Reschedules the alert to fire after the snooze duration. Tracks snooze count
    /// and preserves the original fire time for context.
    ///
    /// - Parameters:
    ///   - alertId: The ID of the alert to snooze.
    ///   - duration: The snooze duration in seconds (e.g., 60 for 1 minute).
    /// - Throws: `AlertError.alertNotFound` if the alert doesn't exist.
    /// - Throws: `AlertError.meetingAlreadyStarted` if the meeting has already started.
    /// - Throws: `AlertError.snoozePastMeetingStart` if the snooze would fire after the meeting starts.
    public func snooze(alertId: String, duration: TimeInterval) async throws {
        guard let existingAlert = self.alerts[alertId] else {
            throw AlertError.alertNotFound(alertId: alertId)
        }

        let now = self.dateProvider()

        // Cannot snooze if meeting has already started
        if existingAlert.eventStartTime <= now {
            throw AlertError.meetingAlreadyStarted
        }

        // Calculate new fire time
        let newFireTime = now.addingTimeInterval(duration)

        // Cannot snooze past meeting start
        if newFireTime >= existingAlert.eventStartTime {
            throw AlertError.snoozePastMeetingStart
        }

        // Create snoozed alert with updated fire time
        let snoozedAlert = existingAlert.snoozed(until: newFireTime)

        // Cancel the old alert timer
        await self.scheduler.cancel(alertId: alertId)

        // Schedule the new snoozed alert
        self.alerts[alertId] = snoozedAlert
        await self.scheduleTimer(for: snoozedAlert)
        await self.persistAlerts()
    }

    /// Reconciles alerts with a new set of events.
    /// Removes alerts for deleted events and schedules new ones.
    public func reconcile(newEvents: [CalendarEvent], settings: SettingsStore) async {
        let newEventIds = Set(newEvents.map(\.id))

        // Cancel alerts for events that no longer exist
        let orphanedEventIds = Set(alerts.values.map(\.eventId)).subtracting(newEventIds)
        for eventId in orphanedEventIds {
            await self.cancelAlerts(for: eventId)
        }

        // Clear acknowledgments for events that no longer exist
        self.acknowledgedEventIds = self.acknowledgedEventIds.intersection(newEventIds)

        // Schedule alerts for new/updated events
        await self.scheduleAlerts(for: newEvents, settings: settings)
    }

    /// Recovers scheduled alerts after app relaunch.
    /// Re-schedules timers for persisted alerts that are still in the future.
    public func reconcileOnRelaunch() async throws {
        guard !self.isInitialized else { return }
        self.isInitialized = true

        let persistedAlerts = try await alertsStore.load()
        let now = self.dateProvider()

        for alert in persistedAlerts where alert.scheduledFireTime > now {
            self.alerts[alert.id] = alert
            await self.scheduleTimer(for: alert)
        }
    }

    // MARK: - Back-to-Back Configuration

    /// Sets the back-to-back context provider for smart alert handling.
    ///
    /// When set, the AlertEngine will check for back-to-back situations before firing alerts.
    /// If the user is in a meeting and the upcoming meeting is back-to-back, stage 1 alerts
    /// will be downgraded to notification banners instead of modal windows.
    ///
    /// - Parameter provider: A closure that returns the back-to-back context for a given alert.
    public func setBackToBackContextProvider(
        _ provider: @escaping @Sendable (ScheduledAlert) async -> BackToBackAlertContext
    ) {
        self.backToBackContextProvider = provider
    }

    /// Clears the back-to-back context provider.
    public func clearBackToBackContextProvider() {
        self.backToBackContextProvider = nil
    }

    // MARK: - Missed Alert Handling

    /// Grace period for "meeting just started" alerts (5 minutes).
    private static let missedAlertGracePeriod: TimeInterval = 5 * 60

    /// Checks for alerts that should have fired during sleep.
    ///
    /// Returns missed alerts categorized by how to handle them:
    /// - `.fireNow`: Meeting hasn't started - fire alert immediately
    /// - `.meetingJustStarted`: Meeting started <5 min ago - show "Meeting started!" alert
    /// - `.tooOld`: Meeting started >5 min ago - just remove the alert
    ///
    /// Call this after system wake to recover from missed alerts.
    /// Alerts are delivered through the AlertDelivery delegate and removed from the store.
    ///
    /// - Returns: Array of missed alert results for processing by the caller.
    public func checkForMissedAlerts() async -> [MissedAlertResult] {
        let now = self.dateProvider()
        var results: [MissedAlertResult] = []

        // Find alerts that were due in the past (missed during sleep)
        let missedAlerts = self.alerts.values.filter { $0.scheduledFireTime < now }

        for alert in missedAlerts {
            let timeSinceMeetingStart = now.timeIntervalSince(alert.eventStartTime)
            let result: MissedAlertResult

            if timeSinceMeetingStart < 0 {
                // Meeting hasn't started yet - fire alert now
                result = .fireNow(alert)
                await self.delivery.deliver(alert: alert)
            } else if timeSinceMeetingStart < Self.missedAlertGracePeriod {
                // Meeting started within grace period - still worth alerting
                result = .meetingJustStarted(alert)
                await self.delivery.deliver(alert: alert)
            } else {
                // Meeting too old - just clean up
                result = .tooOld(alert)
            }

            results.append(result)

            // Remove the processed alert
            await self.scheduler.cancel(alertId: alert.id)
            self.alerts.removeValue(forKey: alert.id)
        }

        if !results.isEmpty {
            await self.persistAlerts()
        }

        return results
    }

    // MARK: - Private Helpers

    private func createAlert(
        for event: CalendarEvent,
        stage: AlertStage,
        fireTime: Date
    ) -> ScheduledAlert {
        ScheduledAlert(
            id: "\(event.id)-\(stage.rawValue)",
            eventId: event.id,
            stage: stage,
            scheduledFireTime: fireTime,
            snoozeCount: 0,
            originalFireTime: nil,
            eventTitle: event.title,
            eventStartTime: event.startTime
        )
    }

    private func scheduleAlert(_ alert: ScheduledAlert) async {
        // Only schedule if not already scheduled or if this is a newer version
        if let existing = alerts[alert.id] {
            if existing.scheduledFireTime == alert.scheduledFireTime {
                return
            }
            // Cancel existing timer for this alert
            await self.scheduler.cancel(alertId: alert.id)
        }

        self.alerts[alert.id] = alert
        await self.scheduleTimer(for: alert)
    }

    private func scheduleTimer(for alert: ScheduledAlert) async {
        await self.scheduler.schedule(
            alertId: alert.id,
            fireDate: alert.scheduledFireTime
        ) { [weak self] in
            Task { await self?.handleAlertFired(alertId: alert.id) }
        }
    }

    private func handleAlertFired(alertId: String) async {
        guard let alert = alerts[alertId] else { return }
        self.alerts.removeValue(forKey: alertId)

        // Check for back-to-back context to potentially downgrade the alert
        let shouldDowngrade = await self.shouldDowngradeAlert(alert)

        if shouldDowngrade {
            // Downgrade to notification banner instead of modal
            await self.delivery.deliverDowngraded(alert: alert, reason: .backToBackMeeting)
        } else {
            // Normal alert delivery (modal)
            await self.delivery.deliver(alert: alert)
        }

        await self.persistAlerts()
    }

    /// Determines whether an alert should be downgraded based on back-to-back context.
    ///
    /// Stage 1 alerts should be downgraded when:
    /// - User is currently in a meeting
    /// - The alert is for a back-to-back meeting
    ///
    /// Stage 2 alerts are never downgraded (user needs urgent notification).
    private func shouldDowngradeAlert(_ alert: ScheduledAlert) async -> Bool {
        // Only downgrade stage 1 alerts
        guard alert.stage == .stage1 else { return false }

        // Check if we have a back-to-back context provider
        guard let provider = backToBackContextProvider else { return false }

        let context = await provider(alert)

        // Downgrade if user is in a meeting and this is a back-to-back situation
        return context.isInMeeting && context.isBackToBackSituation
    }

    private func persistAlerts() async {
        do {
            try await self.alertsStore.save(Array(self.alerts.values))
        } catch {
            // Log error but don't throw - alert delivery is more important than persistence
        }
    }
}

// MARK: - NoOp Delivery

/// Default no-op delivery for production use before real delivery is wired up.
private struct NoOpAlertDelivery: AlertDelivery {
    func deliver(alert _: ScheduledAlert) async {
        // No-op - real delivery will be implemented in UNUserNotificationCenter integration
    }

    func deliverDowngraded(alert _: ScheduledAlert, reason _: AlertDowngradeReason) async {
        // No-op - real delivery will show notification banner instead of modal
    }
}
