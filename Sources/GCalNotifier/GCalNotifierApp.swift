import AppKit
import GCalNotifierCore
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

    // MARK: - Handlers

    private let firstLaunchHandler = FirstLaunchHandler()
    private let notificationPermissionHandler = NotificationPermissionHandler()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_: Notification) {
        self.terminateIfAlreadyRunning()

        // Set up menu bar
        self.setupMenuBar()

        // Set up global keyboard shortcuts
        ShortcutManager.shared.setup()

        // Set up first launch handler delegate
        self.firstLaunchHandler.setDelegate(self)

        // Handle first launch flow
        Task {
            await self.firstLaunchHandler.handleFirstLaunchIfNeeded()
        }
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
        self.menuController = menuController

        // Create status item controller
        let statusItemController = StatusItemController()
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
