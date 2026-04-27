import Foundation

public actor AlertEngine {
    private let alertsStore: ScheduledAlertsStore
    private let scheduler: AlertScheduler
    private let durableNotificationScheduler: any DurableAlertNotificationScheduler
    private let delivery: AlertDelivery
    private let dateProvider: @Sendable () -> Date

    private var alerts: [String: ScheduledAlert] = [:]
    private var acknowledgedAlertStartTimes: [String: Date] = [:]
    private var isInitialized = false

    /// Provider for back-to-back context. Set this to enable back-to-back detection during alerts.
    private var backToBackContextProvider: (@Sendable (ScheduledAlert) async -> BackToBackAlertContext)?

    /// Provider for presentation mode suppression. Set this to enable screen share/DND detection during alerts.
    private var presentationModeProvider: (@Sendable () async -> AlertDowngradeReason?)?

    /// Grace period for late scheduling when sync happens just after a stage boundary.
    private static let lateStageGracePeriod: TimeInterval = 2 * 60
    private static let localStage2TriggerFreshnessWindow: TimeInterval = 5 * 60

    /// Currently scheduled alerts.
    public var scheduledAlerts: [ScheduledAlert] {
        Array(self.alerts.values)
    }

    /// Alert IDs that have been acknowledged (dismissing only skips that specific stage).
    public var acknowledgedAlerts: Set<String> {
        Set(self.acknowledgedAlertStartTimes.keys)
    }

    // MARK: - Initialization

    /// Creates an AlertEngine with the default dependencies.
    public init(alertsStore: ScheduledAlertsStore) async {
        self.alertsStore = alertsStore
        self.scheduler = DispatchAlertScheduler()
        self.durableNotificationScheduler = NoOpDurableAlertNotificationScheduler()
        self.delivery = NoOpAlertDelivery()
        self.dateProvider = { Date() }
    }

    /// Creates an AlertEngine with custom dependencies (for testing).
    public init(
        alertsStore: ScheduledAlertsStore,
        scheduler: AlertScheduler,
        delivery: AlertDelivery,
        durableNotificationScheduler: any DurableAlertNotificationScheduler = NoOpDurableAlertNotificationScheduler(),
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.alertsStore = alertsStore
        self.scheduler = scheduler
        self.durableNotificationScheduler = durableNotificationScheduler
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
        let filter = EventFilter(settings: settings)

        for event in events {
            guard filter.shouldAlert(for: event) else { continue }

            await self.scheduleStageAlert(
                for: event,
                stage: .stage1,
                minutesBefore: stage1Minutes,
                now: now
            )
            await self.scheduleStageAlert(
                for: event,
                stage: .stage2,
                minutesBefore: stage2Minutes,
                now: now
            )
        }

        await self.persistAlerts()
    }

    /// Cancels all alerts for the given event.
    public func cancelAlerts(for eventId: String) async {
        let alertsToCancel = self.alerts.values.filter { $0.eventId == eventId }
        for alert in alertsToCancel {
            await self.cancelScheduledDelivery(for: alert)
            self.alerts.removeValue(forKey: alert.id)
        }
        await self.persistAlerts()
    }

    /// Marks a specific alert as acknowledged, preventing only that stage from re-firing.
    /// Other stages for the same event will still fire.
    public func acknowledgeAlert(alertId: String, eventStartTime: Date) async {
        self.acknowledgedAlertStartTimes[alertId] = eventStartTime
        await self.cancelAlert(alertId: alertId)
    }

    /// Cancels a specific alert by ID.
    private func cancelAlert(alertId: String) async {
        if let alert = self.alerts[alertId] {
            await self.cancelScheduledDelivery(for: alert)
        } else {
            await self.scheduler.cancel(alertId: alertId)
            await self.durableNotificationScheduler.cancelNotification(alertId: alertId)
        }
        self.alerts.removeValue(forKey: alertId)
        await self.persistAlerts()
    }

    public func snooze(alertId: String, duration: TimeInterval) async throws {
        guard let existingAlert = self.alerts[alertId] else {
            throw AlertError.alertNotFound(alertId: alertId)
        }

        let now = self.dateProvider()

        if existingAlert.eventStartTime <= now {
            throw AlertError.meetingAlreadyStarted
        }

        let newFireTime = now.addingTimeInterval(duration)

        if newFireTime >= existingAlert.eventStartTime {
            throw AlertError.snoozePastMeetingStart
        }

        let snoozedAlert = existingAlert.snoozed(until: newFireTime)

        await self.cancelScheduledDelivery(for: existingAlert)

        self.alerts[alertId] = snoozedAlert
        await self.scheduleTimer(for: snoozedAlert)
        await self.scheduleDurableNotificationIfNeeded(for: snoozedAlert)
        await self.persistAlerts()
    }

    /// Reconciles alerts with a new set of events.
    /// Removes alerts for deleted events and schedules new ones.
    public func reconcile(newEvents: [CalendarEvent], settings: SettingsStore) async {
        let newEventIds = Set(newEvents.map(\.qualifiedId))
        let eventsById = Dictionary(uniqueKeysWithValues: newEvents.map { ($0.qualifiedId, $0) })
        let filter = EventFilter(settings: settings)

        let orphanedEventIds = Set(alerts.values.map(\.eventId)).subtracting(newEventIds)
        for eventId in orphanedEventIds {
            await self.cancelAlerts(for: eventId)
        }

        let stage1Enabled = settings.alertStage1Minutes > 0
        let stage2Enabled = settings.alertStage2Minutes > 0
        let existingAlerts = Array(self.alerts.values)
        var alertIdsToCancel: [String] = []

        for alert in existingAlerts {
            guard let event = eventsById[alert.eventId] else { continue }

            if !filter.shouldAlert(for: event) {
                alertIdsToCancel.append(alert.id)
                continue
            }

            switch alert.stage {
            case .stage1 where !stage1Enabled:
                alertIdsToCancel.append(alert.id)
            case .stage2 where !stage2Enabled:
                alertIdsToCancel.append(alert.id)
            default:
                break
            }
        }

        for alertId in alertIdsToCancel {
            if let alert = self.alerts.removeValue(forKey: alertId) {
                await self.cancelScheduledDelivery(for: alert)
            }
        }

        self.acknowledgedAlertStartTimes = self.acknowledgedAlertStartTimes.filter { alertId, startTime in
            guard let eventId = self.eventId(from: alertId),
                  let event = eventsById[eventId]
            else { return false }
            return event.startTime == startTime
        }

        await self.scheduleAlerts(for: newEvents, settings: settings)
    }

    public func reconcileOnRelaunch() async throws {
        guard !self.isInitialized else { return }
        self.isInitialized = true

        do {
            let persistedAlerts = try await alertsStore.load()
            let now = self.dateProvider()

            for alert in persistedAlerts where alert.scheduledFireTime > now {
                self.alerts[alert.id] = alert
                await self.scheduleTimer(for: alert)
                await self.scheduleDurableNotificationIfNeeded(for: alert)
            }
        } catch {
            self.isInitialized = false
            throw error
        }
    }
}

private extension AlertEngine {
    func createAlert(
        for event: CalendarEvent,
        stage: AlertStage,
        fireTime: Date
    ) -> ScheduledAlert {
        ScheduledAlert(
            id: event.alertIdentifier(for: stage),
            eventId: event.qualifiedId,
            stage: stage,
            scheduledFireTime: fireTime,
            snoozeCount: 0,
            originalFireTime: nil,
            eventTitle: event.title,
            eventStartTime: event.startTime,
            eventEndTime: event.endTime,
            joinURL: event.primaryMeetingURL,
            calendarURL: event.htmlLink,
            notificationPayload: AlertNotificationPayload.make(
                eventTitle: event.title,
                eventStartTime: event.startTime,
                stage: stage
            )
        )
    }

    func scheduleAlert(_ alert: ScheduledAlert) async {
        if let existing = alerts[alert.id] {
            if existing.scheduledFireTime == alert.scheduledFireTime {
                return
            }
            await self.cancelScheduledDelivery(for: existing)
        }

        self.alerts[alert.id] = alert
        await self.scheduleTimer(for: alert)
        await self.scheduleDurableNotificationIfNeeded(for: alert)
    }

    func scheduleStageAlert(
        for event: CalendarEvent,
        stage: AlertStage,
        minutesBefore: Int,
        now: Date
    ) async {
        guard minutesBefore > 0 else { return }

        let alertId = event.alertIdentifier(for: stage)
        guard !self.isAcknowledged(alertId: alertId, eventStartTime: event.startTime) else { return }

        if let existing = self.alerts[alertId], existing.eventStartTime == event.startTime {
            if existing.wasSnoozed {
                return
            }

            if existing.scheduledFireTime <= now {
                return
            }
        }

        let stageFire = event.startTime.addingTimeInterval(-Double(minutesBefore * 60))
        if stageFire > now {
            let alert = self.createAlert(for: event, stage: stage, fireTime: stageFire)
            await self.scheduleAlert(alert)
            return
        }

        guard event.startTime > now else { return }
        let lateBy = now.timeIntervalSince(stageFire)
        guard lateBy <= Self.lateStageGracePeriod else { return }

        let alert = self.createAlert(for: event, stage: stage, fireTime: now)
        await self.scheduleAlert(alert)
    }

    func scheduleTimer(for alert: ScheduledAlert) async {
        await self.scheduler.schedule(
            alertId: alert.id,
            fireDate: alert.scheduledFireTime
        ) { [weak self] in
            Task {
                await self?.handleAlertFired(
                    alertId: alert.id,
                    expectedFireTime: alert.scheduledFireTime
                )
            }
        }
    }

    func scheduleDurableNotificationIfNeeded(for alert: ScheduledAlert) async {
        guard alert.stage == .stage2 else { return }
        await self.durableNotificationScheduler.scheduleNotification(for: alert)
    }

    func cancelScheduledDelivery(for alert: ScheduledAlert) async {
        await self.scheduler.cancel(alertId: alert.id)
        guard alert.stage == .stage2 else { return }
        await self.durableNotificationScheduler.cancelNotification(alertId: alert.id)
    }

    func handleAlertFired(alertId: String, expectedFireTime: Date) async {
        guard let alert = alerts[alertId] else { return }
        guard alert.scheduledFireTime == expectedFireTime else { return }
        guard self.isFreshLocalTrigger(alert) else { return }

        if let reason = await self.checkPresentationModeSuppression() {
            await self.delivery.deliverDowngraded(alert: alert, reason: reason)
            await self.persistAlerts()
            return
        }

        if let reason = await self.shouldDowngradeAlert(alert) {
            await self.delivery.deliverDowngraded(alert: alert, reason: reason)
        } else {
            await self.delivery.deliver(alert: alert)
        }

        await self.persistAlerts()
    }

    func isFreshLocalTrigger(_ alert: ScheduledAlert) -> Bool {
        guard alert.stage == .stage2 else { return true }
        return self.dateProvider().timeIntervalSince(alert.scheduledFireTime) <= Self.localStage2TriggerFreshnessWindow
    }

    func checkPresentationModeSuppression() async -> AlertDowngradeReason? {
        guard let provider = presentationModeProvider else { return nil }
        return await provider()
    }

    func shouldDowngradeAlert(_ alert: ScheduledAlert) async -> AlertDowngradeReason? {
        guard alert.stage == .stage1 else { return nil }
        guard let provider = backToBackContextProvider else { return nil }

        let context = await provider(alert)
        if context.isInMeeting, context.isBackToBackSituation {
            return .backToBackMeeting
        }

        return nil
    }

    func persistAlerts() async {
        do {
            try await self.alertsStore.save(Array(self.alerts.values))
        } catch {
            // Alert delivery is more important than persistence here.
        }
    }

    func eventId(from alertId: String) -> String? {
        for stage in AlertStage.allCases {
            let suffix = "-\(stage.rawValue)"
            guard alertId.hasSuffix(suffix) else { continue }
            return String(alertId.dropLast(suffix.count))
        }
        return nil
    }

    func isAcknowledged(alertId: String, eventStartTime: Date) -> Bool {
        guard let acknowledgedStartTime = self.acknowledgedAlertStartTimes[alertId] else {
            return false
        }

        if acknowledgedStartTime == eventStartTime {
            return true
        }

        self.acknowledgedAlertStartTimes.removeValue(forKey: alertId)
        return false
    }
}

// MARK: - Alert Suppression Providers

public extension AlertEngine {
    /// Sets back-to-back context provider. Stage 1 alerts are downgraded to banners when user is in a meeting.
    func setBackToBackContextProvider(
        _ provider: @escaping @Sendable (ScheduledAlert) async -> BackToBackAlertContext
    ) {
        self.backToBackContextProvider = provider
    }

    /// Clears the back-to-back context provider.
    func clearBackToBackContextProvider() {
        self.backToBackContextProvider = nil
    }

    /// Sets presentation mode provider for suppression during screen share/DND.
    func setPresentationModeProvider(
        _ provider: @escaping @Sendable () async -> AlertDowngradeReason?
    ) {
        self.presentationModeProvider = provider
    }

    /// Clears the presentation mode provider.
    func clearPresentationModeProvider() {
        self.presentationModeProvider = nil
    }
}

// MARK: - Missed Alert Handling

public extension AlertEngine {
    private static let missedAlertGracePeriod: TimeInterval = 5 * 60 // 5 minutes

    /// Checks for alerts that missed during sleep. Returns categorized results for handling.
    func checkForMissedAlerts() async -> [MissedAlertResult] {
        let now = self.dateProvider()
        var results: [MissedAlertResult] = []

        // Find alerts that were due in the past (missed during sleep)
        let missedAlerts = self.alerts.values.filter { $0.scheduledFireTime < now }

        for alert in missedAlerts {
            let timeSinceMeetingStart = now.timeIntervalSince(alert.eventStartTime)
            let result: MissedAlertResult
            var shouldKeepAlert = false

            if timeSinceMeetingStart < 0 {
                // Meeting hasn't started yet - fire alert now
                result = .fireNow(alert)
                await self.delivery.deliver(alert: alert)
                shouldKeepAlert = true
            } else if timeSinceMeetingStart < Self.missedAlertGracePeriod {
                // Meeting started within grace period - still worth alerting
                result = .meetingJustStarted(alert)
                await self.delivery.deliver(alert: alert)
                shouldKeepAlert = true
            } else {
                // Meeting too old - just clean up
                result = .tooOld(alert)
            }

            results.append(result)

            // Cancel any pending schedule for the missed alert.
            await self.cancelScheduledDelivery(for: alert)

            if shouldKeepAlert {
                self.alerts[alert.id] = self.updatedAlertForMissed(alert, now: now)
            } else {
                self.alerts.removeValue(forKey: alert.id)
            }
        }

        if !results.isEmpty {
            await self.persistAlerts()
        }

        return results
    }

    private func updatedAlertForMissed(_ alert: ScheduledAlert, now: Date) -> ScheduledAlert {
        ScheduledAlert(
            id: alert.id,
            eventId: alert.eventId,
            stage: alert.stage,
            scheduledFireTime: now,
            snoozeCount: alert.snoozeCount,
            originalFireTime: alert.originalFireTime,
            eventTitle: alert.eventTitle,
            eventStartTime: alert.eventStartTime,
            eventEndTime: alert.eventEndTime,
            joinURL: alert.joinURL,
            calendarURL: alert.calendarURL,
            notificationPayload: alert.notificationPayload
        )
    }
}
