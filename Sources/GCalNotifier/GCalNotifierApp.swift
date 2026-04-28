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
    var eventCache: EventCache?

    let settingsStore = SettingsStore()

    /// Alert window controller for meeting alerts
    var alertWindowController: AlertWindowController?

    var alertEngine: AlertEngine?

    /// Alert delivery implementation
    var alertDelivery: WindowAlertDelivery?

    /// Readiness gate that must complete before sync is allowed to reconcile alerts.
    let alertReadinessGate = AlertReadinessGate<AlertEngine>()

    /// OAuth provider for Google authentication
    private let oauthProvider = GoogleOAuthProvider()

    /// App state store for sync tokens (internal for extension access)
    var appStateStore: AppStateStore?

    /// Scheduled alerts persistence
    var alertsStore: ScheduledAlertsStore?

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

    /// Task for reconciling cached alerts after alert-affecting settings change.
    var alertSettingsReconcileTask: Task<Void, Never>?

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
        self.setupAlertSettingsReconciliation()
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
            Task { @MainActor [weak self] in
                await self?.resolveNotificationWarningAction()
            }
        }
        menuController.onOpenLoginItemsSettings = {
            LaunchAtLoginManager.shared.openLoginItemsSettings()
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
        self.startReliabilityDiagnosticsMonitoring()

        // Create status item controller
        let statusItemController = StatusItemController()
        statusItemController.onMenuWillPrepare = { [weak self, weak menuController] in
            await menuController?.loadEventsFromCache()
            self?.refreshReliabilityDiagnostics()
        }
        statusItemController.onMenuWillOpen = { [weak menuController] in
            menuController?.buildMenu() ?? NSMenu()
        }

        // Configure with EventCache if available for countdown display
        if let eventCache {
            statusItemController.configure(eventCache: eventCache, settings: self.settingsStore)
        }

        self.statusItemController = statusItemController
    }

    private func startReliabilityDiagnosticsMonitoring() {
        self.notificationPermissionHandler.setDelegate(self)
        self.notificationPermissionHandler.startMonitoring()
        Task { [weak self] in
            guard let self else { return }
            let status = await self.notificationPermissionHandler.checkPermission()
            self.menuController?.updateNotificationAuthorizationStatus(status)
            self.refreshReliabilityDiagnostics()
        }
    }

    private func refreshReliabilityDiagnostics() {
        self.menuController?.updateNotificationAuthorizationStatus(
            self.notificationPermissionHandler.authorizationStatus
        )
        self.menuController?.updateLaunchAtLoginStatus(LaunchAtLoginManager.shared.checkStatus())
    }

    private func resolveNotificationWarningAction() async {
        let status = await self.notificationPermissionHandler.checkPermission()
        Logger.app.info("Notification reliability warning selected: \(String(describing: status))")
        if status == .notDetermined {
            let granted = await self.notificationPermissionHandler.requestAuthorizationIfNotDetermined()
            if !granted {
                self.notificationPermissionHandler.openNotificationSettings()
            }
        } else {
            self.notificationPermissionHandler.openNotificationSettings()
        }
        self.refreshReliabilityDiagnostics()
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

        // Stop settings-triggered reconciliation
        self.alertSettingsReconcileTask?.cancel()
        self.alertSettingsReconcileTask = nil
        self.settingsStore.setAlertAffectingSettingsChangeHandler(nil)

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
        do {
            _ = try await self.requireAlertEngineReady()
        } catch {
            Logger.app.error(
                "AlertEngine not ready after authentication; initial sync blocked: \(error.localizedDescription)"
            )
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

        if let alertEngine = try? await self.requireAlertEngineReady() {
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
        // Initial setup complete; setup guidance remains visible until OAuth is configured.
    }

    nonisolated func firstLaunchHandlerDidSignIn(_: FirstLaunchHandler) async {
        // Post-sign-in follow-up is handled by existing services.
    }
}

// MARK: - NotificationPermissionHandlerDelegate

extension AppDelegate: NotificationPermissionHandlerDelegate {
    func permissionStatusDidChange(_: NotificationPermissionHandler, isGranted _: Bool) async {
        self.refreshReliabilityDiagnostics()
    }
}
