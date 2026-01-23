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
        await self.delivery.deliver(alert: alert)
        await self.persistAlerts()
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
}
