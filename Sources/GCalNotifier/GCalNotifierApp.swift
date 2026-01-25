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

    /// Settings window (created on demand)
    private var settingsWindow: NSWindow?

    // MARK: - Menu Bar

    private var statusItemController: StatusItemController?
    private var menuController: MenuController?

    // MARK: - Core Services

    /// Local storage for calendar events - shared across components
    private var eventCache: EventCache?

    /// Settings store - shared across components
    private let settingsStore = SettingsStore()

    /// Alert window controller for meeting alerts
    private var alertWindowController: AlertWindowController?

    /// OAuth provider for Google authentication
    private let oauthProvider = GoogleOAuthProvider()

    /// App state store for sync tokens
    private var appStateStore: AppStateStore?

    /// Calendar sync engine - orchestrates sync operations
    private var syncEngine: SyncEngine?

    // MARK: - Handlers

    private let firstLaunchHandler = FirstLaunchHandler()
    private let notificationPermissionHandler = NotificationPermissionHandler()

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
        // Create EventCache - this may fail if filesystem is unavailable
        do {
            self.eventCache = try EventCache()
            Logger.app.info("EventCache initialized successfully")
        } catch {
            // Log error but continue - app can still function in limited capacity
            // EventCache failure is not fatal; sync just won't persist
            Logger.app.error("Failed to create EventCache: \(error.localizedDescription)")
        }

        // Create AppStateStore for sync tokens
        do {
            self.appStateStore = try AppStateStore()
            Logger.app.info("AppStateStore initialized successfully")
        } catch {
            Logger.app.error("Failed to create AppStateStore: \(error.localizedDescription)")
        }

        // Create SyncEngine if all dependencies are available
        if let eventCache, let appStateStore {
            let httpClient = URLSessionHTTPClient()
            let calendarClient = GoogleCalendarClient(httpClient: httpClient, tokenProvider: self.oauthProvider)
            let eventFilter = EventFilter(settings: self.settingsStore)

            self.syncEngine = SyncEngine(
                calendarClient: calendarClient,
                eventCache: eventCache,
                appState: appStateStore,
                eventFilter: eventFilter
            )
            Logger.app.info("SyncEngine initialized successfully")
        } else {
            Logger.app.warning("SyncEngine not created: missing EventCache or AppStateStore")
        }

        // Create AlertWindowController
        self.alertWindowController = AlertWindowController()

        // Load stored OAuth credentials (async)
        Task {
            do {
                try await self.oauthProvider.loadStoredCredentials()
                let state = await self.oauthProvider.state
                Logger.app.info("OAuth state after loading credentials: \(String(describing: state))")
            } catch {
                Logger.app.error("Failed to load OAuth credentials: \(error.localizedDescription)")
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
        menuController.onQuit = {
            NSApp.terminate(nil)
        }

        // Configure with EventCache if available
        if let eventCache {
            menuController.configure(eventCache: eventCache)
        }

        self.menuController = menuController

        // Create status item controller
        let statusItemController = StatusItemController()
        statusItemController.onMenuWillPrepare = { [weak menuController] in
            await menuController?.loadEventsFromCache()
        }
        statusItemController.onMenuWillOpen = { [weak menuController] in
            menuController?.buildMenu() ?? NSMenu()
        }
        self.statusItemController = statusItemController
    }

    func applicationWillTerminate(_: Notification) {
        // Clean up keyboard shortcuts
        ShortcutManager.shared.teardown()
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
        let hostingController = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "GCalNotifier Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 500, height: 400))
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.settingsWindow = window
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
