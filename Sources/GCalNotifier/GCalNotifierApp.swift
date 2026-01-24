import AppKit
import GCalNotifierCore
import SwiftUI

@main
struct GCalNotifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Handlers

    private let firstLaunchHandler = FirstLaunchHandler()
    private let notificationPermissionHandler = NotificationPermissionHandler()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_: Notification) {
        self.terminateIfAlreadyRunning()

        // Set up global keyboard shortcuts
        ShortcutManager.shared.setup()

        // Set up first launch handler delegate
        self.firstLaunchHandler.setDelegate(self)

        // Handle first launch flow
        Task {
            await self.firstLaunchHandler.handleFirstLaunchIfNeeded()
        }
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
