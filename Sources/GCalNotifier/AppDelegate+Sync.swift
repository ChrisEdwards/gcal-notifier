import GCalNotifierCore
import OSLog

// MARK: - AppDelegate Sync Operations

extension AppDelegate {
    /// Performs a sync operation using the shared SyncEngine and reschedules alerts.
    /// Called from menu bar Refresh and can be reused by other sync triggers.
    func performSync() async {
        guard let syncEngine else {
            Logger.app.warning("SyncEngine not available, cannot perform sync")
            return
        }

        Logger.app.info("Performing sync")
        do {
            let result = try await syncEngine.sync(calendarId: "primary")
            Logger.app.info("Sync complete: \(result.events.count) events")
            await self.scheduleAlertsForEvents(result.events)

            // Update status bar with new events
            await self.statusItemController?.loadEventsFromCache()

            // Schedule next automatic sync based on upcoming events
            let interval = await syncEngine.calculatePollingInterval(events: result.events)
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
        guard let syncEngine, let appStateStore else {
            Logger.app.warning("SyncEngine or AppStateStore not available")
            return .failure("Sync not available")
        }

        Logger.app.info("Performing force full sync")
        do {
            // Clear sync tokens to force a full sync
            try await appStateStore.clearAllSyncTokens()

            let result = try await syncEngine.sync(calendarId: "primary")
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

    /// Schedules alerts for the given events using the AlertEngine.
    func scheduleAlertsForEvents(_ events: [CalendarEvent]) async {
        guard let alertEngine else {
            Logger.app.warning("AlertEngine not available, cannot schedule alerts")
            return
        }

        Logger.app.info("Scheduling alerts for \(events.count) events")
        await alertEngine.scheduleAlerts(for: events, settings: self.settingsStore)

        let scheduledCount = await alertEngine.scheduledAlerts.count
        Logger.app.info("AlertEngine now has \(scheduledCount) scheduled alerts")
    }
}
