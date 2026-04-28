import GCalNotifierCore
import OSLog

// MARK: - Alert Engine

extension AppDelegate {
    func setupAlertEngine() {
        self.alertReadinessGate.start(Task { @MainActor in
            try await self.initializeAlertEngine()
        })
    }

    private func initializeAlertEngine() async throws -> AlertEngine {
        guard let eventCache, let alertsStore, let alertWindowController else {
            Logger.app.error("AlertEngine readiness failed: missing dependencies")
            throw AlertSystemReadinessError.missingDependencies
        }

        let alertScheduler = DispatchAlertScheduler()
        let notificationScheduler = await NotificationScheduler()
        let delivery = WindowAlertDelivery(
            windowController: alertWindowController,
            eventCache: eventCache,
            settings: self.settingsStore,
            scheduler: notificationScheduler
        )

        delivery.onAlertDelivered = { [weak self] in
            Task { @MainActor in
                self?.statusItemController?.updateDisplay()
            }
        }
        self.alertDelivery = delivery

        let engine = AlertEngine(
            alertsStore: alertsStore,
            scheduler: alertScheduler,
            delivery: delivery,
            durableNotificationScheduler: notificationScheduler
        )
        await self.configureAlertEngineProviders(engine)
        self.alertEngine = engine
        await delivery.setAlertEngine(engine)

        try await engine.reconcileOnRelaunch()
        Logger.app.info("AlertEngine reconciled on relaunch")
        Logger.app.info("AlertEngine initialized successfully")
        return engine
    }

    func requireAlertEngineReady() async throws -> AlertEngine {
        if let alertEngine {
            return alertEngine
        }
        do {
            return try await self.alertReadinessGate.wait()
        } catch AlertReadinessGateError.notStarted {
            Logger.app.error("AlertEngine readiness failed: setup was not started")
            throw AlertSystemReadinessError.notStarted
        } catch {
            throw error
        }
    }

    private func configureAlertEngineProviders(_ engine: AlertEngine) async {
        await self.configureBackToBackProvider(engine)
        await self.configurePresentationModeProvider(engine)
    }

    private func configureBackToBackProvider(_ engine: AlertEngine) async {
        guard let syncEngine else { return }
        await engine.setBackToBackContextProvider { alert in
            guard let current = await syncEngine.currentMeeting() else {
                return .none
            }
            let next = await syncEngine.nextBackToBackMeeting()
            let isBackToBack = next?.qualifiedId == alert.eventId
            return BackToBackAlertContext(
                isInMeeting: true,
                isBackToBackSituation: isBackToBack,
                currentMeeting: current
            )
        }
    }

    private func configurePresentationModeProvider(_ engine: AlertEngine) async {
        let settingsStore = self.settingsStore
        await engine.setPresentationModeProvider {
            guard settingsStore.suppressDuringScreenShare else { return nil }
            let state = await MainActor.run { PresentationModeDetector.shared.detect() }
            return state.alertDowngradeReason
        }
    }
}

@MainActor
final class AlertReadinessGate<Value: Sendable> {
    private var task: Task<Value, Error>?

    func start(_ task: Task<Value, Error>) {
        self.task = task
    }

    func wait() async throws -> Value {
        guard let task else {
            throw AlertReadinessGateError.notStarted
        }
        return try await task.value
    }
}

enum AlertReadinessGateError: Error, Equatable {
    case notStarted
}

enum AlertSystemReadinessError: LocalizedError, Equatable {
    case missingDependencies
    case notStarted

    var errorDescription: String? {
        switch self {
        case .missingDependencies:
            "Alert system dependencies are unavailable."
        case .notStarted:
            "Alert system initialization was not started."
        }
    }
}
