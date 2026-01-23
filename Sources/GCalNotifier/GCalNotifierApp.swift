import AppKit
import SwiftUI

@main
struct GCalNotifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        self.terminateIfAlreadyRunning()
    }

    private func terminateIfAlreadyRunning() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if runningApps.count > 1 {
            NSApp.terminate(nil)
        }
    }
}
