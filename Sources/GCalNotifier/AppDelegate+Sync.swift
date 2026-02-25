import GCalNotifierCore
import OSLog

// MARK: - AppDelegate Sync Operations

extension AppDelegate {
    /// Performs a sync operation using the shared SyncEngine and reschedules alerts.
    /// Called from menu bar Refresh and can be reused by other sync triggers.
    func performSync() async {
        let canSync = await self.canPerformSync()
        guard canSync else {
            Logger.app.info("Skipping sync: authentication required")
            return
        }

        guard let syncEngine else {
            Logger.app.warning("SyncEngine not available, cannot perform sync")
            return
        }

        Logger.app.info("Performing sync")
        do {
            let calendarIds = await self.resolveCalendarIdsForSync()
            let result = try await syncEngine.syncAllCalendars(calendarIds)
            Logger.app.info(
                "Sync complete: \(result.events.count) events across \(result.successfulCalendars.count) calendars"
            )
            if !result.failedCalendars.isEmpty {
                Logger.app.warning("Sync failed for \(result.failedCalendars.count) calendars")
            }
            await self.scheduleAlertsForEvents(result.events)

            // Update status bar with new events
            await self.statusItemController?.loadEventsFromCache()

            // Schedule next automatic sync based on upcoming events
            let interval = await syncEngine.calculatePollingInterval(events: result.filteredEvents)
            self.scheduleSyncPolling(interval: interval.rawValue)
        } catch {
            Logger.app.error("Sync failed: \(error.localizedDescription)")
            // On failure, retry with idle interval
            self.scheduleSyncPolling(interval: PollingInterval.normal.rawValue)
        }
    }

    /// Starts automatic background sync polling.
    /// Call this after authentication completes.
    func startSyncPolling() {
        Logger.app.info("Starting automatic sync polling")
        // Start with idle interval - first sync will adjust based on events
        self.scheduleSyncPolling(interval: PollingInterval.normal.rawValue)
    }

    /// Stops automatic background sync polling.
    func stopSyncPolling() {
        self.syncPollingTask?.cancel()
        self.syncPollingTask = nil
        Logger.app.info("Stopped sync polling")
    }

    /// Schedules the next sync poll after the specified interval.
    private func scheduleSyncPolling(interval: TimeInterval) {
        // Cancel any existing polling task
        self.syncPollingTask?.cancel()

        Logger.app.debug("Scheduling next sync in \(Int(interval)) seconds")

        self.syncPollingTask = Task {
            do {
                try await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self.performSync()
            } catch {
                // Task was cancelled, ignore
            }
        }
    }

    /// Performs a force full sync by clearing tokens first, then syncing.
    /// Returns result for UI feedback.
    func performForceFullSync() async -> ForceSyncResult {
        let canSync = await self.canPerformSync()
        guard canSync else {
            Logger.app.warning("Force sync requested without authentication")
            return .failure("Please sign in first.")
        }

        guard let syncEngine, let appStateStore else {
            Logger.app.warning("SyncEngine or AppStateStore not available")
            return .failure("Sync not available")
        }

        Logger.app.info("Performing force full sync")
        do {
            // Clear sync tokens to force a full sync
            try await appStateStore.clearAllSyncTokens()

            let calendarIds = await self.resolveCalendarIdsForSync(forceRefresh: true)
            let result = try await syncEngine.syncAllCalendars(calendarIds)
            Logger.app.info("Force full sync complete: \(result.events.count) events")

            // Update last full sync time
            try await appStateStore.setLastFullSync(Date())

            await self.scheduleAlertsForEvents(result.events)

            // Update status bar with new events
            await self.statusItemController?.loadEventsFromCache()

            return .success(eventCount: result.events.count)
        } catch {
            Logger.app.error("Force full sync failed: \(error.localizedDescription)")
            return .failure("Sync failed: \(error.localizedDescription)")
        }
    }

    private func resolveCalendarIdsForSync(forceRefresh: Bool = false) async -> [String] {
        let configuredCalendars = self.dedupedCalendarIds(self.settingsStore.enabledCalendars)
        if !configuredCalendars.isEmpty {
            return configuredCalendars
        }

        if !forceRefresh, !self.cachedCalendarIds.isEmpty {
            return self.cachedCalendarIds
        }

        guard let calendarClient = self.calendarClient else {
            Logger.app.warning("Calendar client unavailable, falling back to primary calendar")
            return ["primary"]
        }

        do {
            let calendars = try await calendarClient.fetchCalendarList()
            let ids = self.dedupedCalendarIds(calendars.map(\CalendarInfo.id))
            if ids.isEmpty {
                Logger.app.warning("Calendar list empty, falling back to primary calendar")
                return ["primary"]
            }
            self.cachedCalendarIds = ids
            return ids
        } catch {
            Logger.app.error("Failed to fetch calendar list: \(error.localizedDescription)")
            if !self.cachedCalendarIds.isEmpty {
                return self.cachedCalendarIds
            }
            return ["primary"]
        }
    }

    private func dedupedCalendarIds(_ calendarIds: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for calendarId in calendarIds {
            guard !seen.contains(calendarId) else { continue }
            seen.insert(calendarId)
            result.append(calendarId)
        }
        return result
    }

    /// Reconciles alerts for the given events using the AlertEngine.
    func scheduleAlertsForEvents(_ events: [CalendarEvent]) async {
        guard let alertEngine else {
            Logger.app.warning("AlertEngine not available, cannot schedule alerts")
            return
        }

        Logger.app.info("Reconciling alerts for \(events.count) events")
        await alertEngine.reconcile(newEvents: events, settings: self.settingsStore)

        let scheduledCount = await alertEngine.scheduledAlerts.count
        Logger.app.info("AlertEngine now has \(scheduledCount) scheduled alerts")
    }
}
