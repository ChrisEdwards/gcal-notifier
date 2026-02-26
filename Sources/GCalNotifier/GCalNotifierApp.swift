import AppKit
import GCalNotifierCore
import OSLog
import SwiftUI

@main
struct GCalNotifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar apps don't need a default scene, but SwiftUI requires one
        // Settings window is created directly via NSWindow in AppDelegate
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Window Management

    private var settingsWindow: NSWindow?

    // MARK: - Menu Bar

    var statusItemController: StatusItemController?
    private var menuController: MenuController?

    // MARK: - Core Services

    /// Local storage for calendar events - shared across components
    private var eventCache: EventCache?

    let settingsStore = SettingsStore()

    /// Alert window controller for meeting alerts
    private var alertWindowController: AlertWindowController?

    var alertEngine: AlertEngine?

    /// Alert delivery implementation
    private var alertDelivery: WindowAlertDelivery?

    /// OAuth provider for Google authentication
    private let oauthProvider = GoogleOAuthProvider()

    /// App state store for sync tokens (internal for extension access)
    var appStateStore: AppStateStore?

    /// Scheduled alerts persistence
    private var alertsStore: ScheduledAlertsStore?

    /// Calendar sync engine - orchestrates sync operations (internal for extension access)
    var syncEngine: SyncEngine?

    /// Calendar client for fetching calendar list when syncing all calendars (internal for extension access).
    var calendarClient: GoogleCalendarClient?

    /// Cached calendar IDs for "all calendars" syncing (internal for extension access).
    var cachedCalendarIds: [String] = []

    // MARK: - Handlers

    private let firstLaunchHandler = FirstLaunchHandler()
    private let notificationPermissionHandler = NotificationPermissionHandler()
    private let sleepWakeHandler = SleepWakeHandler()

    /// Task monitoring OAuth state for auto-starting sync
    private var authStateMonitorTask: Task<Void, Never>?

    /// Task for automatic background sync polling (internal for extension access)
    var syncPollingTask: Task<Void, Never>?

    /// Tracks last known auth state to detect transitions
    private var lastKnownAuthState: AuthState = .unconfigured

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_: Notification) {
        self.terminateIfAlreadyRunning()

        // Initialize core services
        self.setupCoreServices()

        // Set up menu bar
        self.setupMenuBar()

        // Set up global keyboard shortcuts with dependencies
        self.setupShortcuts()

        // Set up first launch handler delegate
        self.firstLaunchHandler.setDelegate(self)

        // Handle first launch flow
        Task {
            await self.firstLaunchHandler.handleFirstLaunchIfNeeded()
        }
    }

    private func setupCoreServices() {
        self.setupDataStores()
        self.setupSyncEngine()
        self.alertWindowController = AlertWindowController()
        self.setupAlertEngine()
        self.setupOAuthAndSync()
        self.sleepWakeHandler.setDelegate(self)
        self.sleepWakeHandler.startMonitoring()
    }

    private func setupDataStores() {
        do {
            self.eventCache = try EventCache()
            Logger.app.info("EventCache initialized successfully")
        } catch {
            Logger.app.error("Failed to create EventCache: \(error.localizedDescription)")
        }

        do {
            self.appStateStore = try AppStateStore()
            Logger.app.info("AppStateStore initialized successfully")
        } catch {
            Logger.app.error("Failed to create AppStateStore: \(error.localizedDescription)")
        }

        do {
            self.alertsStore = try ScheduledAlertsStore()
            Logger.app.info("ScheduledAlertsStore initialized successfully")
        } catch {
            Logger.app.error("Failed to create ScheduledAlertsStore: \(error.localizedDescription)")
        }
    }

    private func setupSyncEngine() {
        guard let eventCache, let appStateStore else {
            Logger.app.warning("SyncEngine not created: missing EventCache or AppStateStore")
            return
        }
        let httpClient = URLSessionHTTPClient()
        let calendarClient = GoogleCalendarClient(httpClient: httpClient, tokenProvider: self.oauthProvider)
        let eventFilter = EventFilter(settings: self.settingsStore)
        self.calendarClient = calendarClient
        self.syncEngine = SyncEngine(
            calendarClient: calendarClient,
            eventCache: eventCache,
            appState: appStateStore,
            eventFilter: eventFilter
        )
        Logger.app.info("SyncEngine initialized successfully")
    }

    private func setupOAuthAndSync() {
        Task {
            do {
                try await self.oauthProvider.loadStoredCredentials()
                let state = await self.oauthProvider.state
                Logger.app.info("OAuth state after loading credentials: \(String(describing: state))")
                self.lastKnownAuthState = state
                if state.canMakeApiCalls {
                    await self.handleAuthenticationCompleted(showSetupCompletion: false)
                }
            } catch {
                Logger.app.error("Failed to load OAuth credentials: \(error.localizedDescription)")
            }
            self.startAuthStateMonitoring()
        }
    }

    /// Starts monitoring OAuth state for changes to trigger sync.
    private func startAuthStateMonitoring() {
        // Cancel any existing monitor
        self.authStateMonitorTask?.cancel()

        self.authStateMonitorTask = Task {
            while !Task.isCancelled {
                // Poll auth state every second
                try? await Task.sleep(for: .seconds(1))

                let currentState = await self.oauthProvider.state

                // Detect transition to authenticated state
                if currentState.canMakeApiCalls, !self.lastKnownAuthState.canMakeApiCalls {
                    Logger.app.info("Auth state transitioned to authenticated, starting sync")
                    await self.handleAuthenticationCompleted(showSetupCompletion: true)
                } else if !currentState.canMakeApiCalls, self.lastKnownAuthState.canMakeApiCalls {
                    Logger.app.info("Auth state transitioned to unauthenticated, stopping sync")
                    await self.handleAuthenticationRevoked()
                }

                self.lastKnownAuthState = currentState
            }
        }
    }

    private func setupShortcuts() {
        // Configure ShortcutManager with dependencies if available
        if let eventCache, let alertWindowController {
            ShortcutManager.shared.configure(
                eventCache: eventCache,
                alertWindowController: alertWindowController,
                settings: self.settingsStore
            )
        }

        // Set up keyboard shortcut handlers
        ShortcutManager.shared.setup()
    }

    private func setupMenuBar() {
        // Create menu controller
        let menuController = MenuController()
        menuController.updateSetupRequired(true) // Start in setup mode
        menuController.onSettings = { [weak self] in
            self?.showSettingsWindow()
        }
        menuController.onOpenNotificationSettings = { [weak self] in
            self?.notificationPermissionHandler.openNotificationSettings()
        }
        menuController.onQuit = {
            NSApp.terminate(nil)
        }
        menuController.onRefresh = { [weak self] in
            guard let self else { return }
            Task { await self.performSync() }
        }

        // Configure with EventCache if available
        if let eventCache {
            menuController.configure(eventCache: eventCache, settings: self.settingsStore)
        }

        self.menuController = menuController

        self.notificationPermissionHandler.setDelegate(self)
        self.notificationPermissionHandler.startMonitoring()

        // Create status item controller
        let statusItemController = StatusItemController()
        statusItemController.onMenuWillPrepare = { [weak menuController] in
            await menuController?.loadEventsFromCache()
        }
        statusItemController.onMenuWillOpen = { [weak menuController] in
            menuController?.buildMenu() ?? NSMenu()
        }

        // Configure with EventCache if available for countdown display
        if let eventCache {
            statusItemController.configure(eventCache: eventCache, settings: self.settingsStore)
        }

        self.statusItemController = statusItemController

        Task { [weak self] in
            guard let self else { return }
            let status = await self.notificationPermissionHandler.checkPermission()
            self.menuController?.updateNotificationPermissionDenied(status == .denied)
        }
    }

    func applicationWillTerminate(_: Notification) {
        // Clean up keyboard shortcuts
        ShortcutManager.shared.teardown()

        // Stop auth monitoring
        self.authStateMonitorTask?.cancel()
        self.authStateMonitorTask = nil

        // Stop sync polling
        self.syncPollingTask?.cancel()
        self.syncPollingTask = nil

        // Stop sleep/wake monitoring
        self.sleepWakeHandler.stopMonitoring()
    }

    private func terminateIfAlreadyRunning() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if runningApps.count > 1 {
            NSApp.terminate(nil)
        }
    }

    /// Shows the settings window, creating it if needed
    private func showSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // Reuse existing window if available
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Create new settings window with SwiftUI content
        let preferencesView = PreferencesView(
            settings: self.settingsStore,
            oauthProvider: self.oauthProvider,
            fetchCalendars: { [weak self] in try await self?.calendarClient?.fetchCalendarList() ?? [] },
            onForceSync: { [weak self] in
                await self?.performForceFullSync() ?? .failure("App not available")
            }
        )
        let hostingController = NSHostingController(rootView: preferencesView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "GCalNotifier Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 650, height: 550))
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.settingsWindow = window
    }
}

// MARK: - Alert Engine

extension AppDelegate {
    private func setupAlertEngine() {
        guard let eventCache, let alertsStore, let alertWindowController else {
            Logger.app.warning("AlertEngine not created: missing dependencies")
            return
        }
        Task {
            let scheduler = await NotificationScheduler()
            let delivery = WindowAlertDelivery(
                windowController: alertWindowController,
                eventCache: eventCache,
                settings: self.settingsStore,
                scheduler: scheduler
            )

            // Update status bar when an alert is delivered
            delivery.onAlertDelivered = { [weak self] in
                Task { @MainActor in
                    self?.statusItemController?.updateDisplay()
                }
            }

            self.alertDelivery = delivery

            let engine = AlertEngine(
                alertsStore: alertsStore,
                scheduler: scheduler,
                delivery: delivery
            )
            await self.configureAlertEngineProviders(engine)
            self.alertEngine = engine
            await MainActor.run { delivery.setAlertEngine(engine) }

            do {
                try await engine.reconcileOnRelaunch()
                Logger.app.info("AlertEngine reconciled on relaunch")
            } catch {
                Logger.app.error("Failed to reconcile alerts: \(error.localizedDescription)")
            }
            Logger.app.info("AlertEngine initialized successfully")
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

// MARK: - Authentication Handling

extension AppDelegate {
    func canPerformSync() async -> Bool {
        let state = await self.oauthProvider.state
        return state.canMakeApiCalls
    }

    /// Called when authentication completes successfully - triggers initial sync and starts polling.
    func handleAuthenticationCompleted(showSetupCompletion: Bool = false) async {
        guard self.syncEngine != nil else {
            Logger.app.warning("SyncEngine not available, cannot start sync after authentication")
            return
        }

        // Update menu to show we're no longer in setup mode
        self.menuController?.updateSetupRequired(false)
        self.statusItemController?.setState(.normal)

        // Trigger initial sync and start automatic polling
        Logger.app.info("Triggering initial sync after authentication")
        await self.performSync()

        if !self.firstLaunchHandler.isSetupCompleted {
            if showSetupCompletion {
                await self.firstLaunchHandler.handleSuccessfulSignIn()
            } else {
                self.firstLaunchHandler.markSetupCompleted()
            }
        }
    }

    func handleAuthenticationRevoked() async {
        self.menuController?.updateSetupRequired(true)
        self.statusItemController?.setState(.oauthNeeded)
        self.stopSyncPolling()
        self.cachedCalendarIds = []

        if let alertEngine {
            await alertEngine.reconcile(newEvents: [], settings: self.settingsStore)
        }

        if let eventCache {
            do {
                try await eventCache.clear()
            } catch {
                Logger.app.error("Failed to clear event cache: \(error.localizedDescription)")
            }
        }

        await self.statusItemController?.loadEventsFromCache()
        Logger.app.info("Cleared cached events and alerts after sign-out")
    }
}

// MARK: - FirstLaunchHandlerDelegate

extension AppDelegate: FirstLaunchHandlerDelegate {
    nonisolated func firstLaunchHandlerShouldRequestNotificationPermission(
        _: FirstLaunchHandler
    ) async -> Bool {
        await self.requestNotificationPermission()
    }

    @MainActor
    private func requestNotificationPermission() async -> Bool {
        await self.notificationPermissionHandler.requestAuthorization()
    }

    nonisolated func firstLaunchHandlerDidCompleteInitialSetup(_: FirstLaunchHandler) async {
        // Initial setup complete - app is now in "setup required" state
        // The menu will show setup instructions until OAuth is configured
    }

    nonisolated func firstLaunchHandlerDidSignIn(_: FirstLaunchHandler) async {
        // Post-sign-in tasks would go here
        // - Fetch calendar list
        // - Enable all calendars
        // - Trigger initial sync
        // These will be handled by the appropriate services when available
    }
}

// MARK: - NotificationPermissionHandlerDelegate

extension AppDelegate: NotificationPermissionHandlerDelegate {
    func permissionStatusDidChange(_: NotificationPermissionHandler, isGranted: Bool) async {
        self.menuController?.updateNotificationPermissionDenied(!isGranted)
    }
}

// MARK: - SleepWakeHandlerDelegate

extension AppDelegate: SleepWakeHandlerDelegate {
    nonisolated func sleepWakeHandlerDidWake(_: SleepWakeHandler) async {
        let engine = await MainActor.run { self.alertEngine }
        if let engine {
            _ = await engine.checkForMissedAlerts()
        }

        Task { @MainActor in
            Logger.app.info("System woke - syncing and rescheduling alerts")
            await self.performSync()
        }
    }

    nonisolated func sleepWakeHandlerWillSleep(_: SleepWakeHandler) async {
        await MainActor.run {
            Logger.app.info("System sleeping - timers may pause")
        }
    }
}
