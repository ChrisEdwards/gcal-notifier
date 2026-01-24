import AppKit
import Foundation
import GCalNotifierCore
import OSLog

// MARK: - FirstLaunchHandlerDelegate

/// Delegate protocol for receiving first launch events.
public protocol FirstLaunchHandlerDelegate: AnyObject, Sendable {
    /// Called when the first launch flow should begin.
    func firstLaunchHandlerShouldRequestNotificationPermission(_ handler: FirstLaunchHandler) async -> Bool

    /// Called when the first launch flow has completed initial setup.
    func firstLaunchHandlerDidCompleteInitialSetup(_ handler: FirstLaunchHandler) async

    /// Called when sign-in is successful and calendars should be fetched.
    func firstLaunchHandlerDidSignIn(_ handler: FirstLaunchHandler) async
}

// MARK: - FirstLaunchHandler

/// Handles first launch experience and onboarding flow.
///
/// On first launch, this handler:
/// 1. Requests notification permission
/// 2. Enables launch at login by default
/// 3. Signals that setup is required (no OAuth credentials yet)
///
/// After successful OAuth sign-in:
/// 1. Fetches calendar list
/// 2. Enables all calendars by default
/// 3. Triggers initial sync
/// 4. Shows success confirmation
///
/// ## Usage
/// ```swift
/// let handler = FirstLaunchHandler()
/// if handler.isFirstLaunch {
///     await handler.handleFirstLaunchIfNeeded()
/// }
/// ```
@MainActor
public final class FirstLaunchHandler {
    // MARK: - Constants

    private static let hasLaunchedKey = "hasLaunchedBefore"
    private static let setupCompletedKey = "setupCompleted"

    /// Detects if running in a test environment to avoid showing modal alerts.
    private static var isRunningTests: Bool {
        // No bundle identifier = running in SPM test environment
        if Bundle.main.bundleIdentifier == nil { return true }
        // Check for XCTest (older framework)
        if NSClassFromString("XCTestCase") != nil { return true }
        // Check for Swift Testing framework via environment
        if ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil { return true }
        if ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil { return true }
        // Check process name for test runner
        let processName = ProcessInfo.processInfo.processName.lowercased()
        if processName.contains("xctest") { return true }
        // Check if running as test bundle
        if Bundle.main.bundlePath.contains(".xctest") { return true }
        if Bundle.main.bundlePath.contains("PackageTests") { return true }
        return false
    }

    // MARK: - Dependencies

    private let logger = Logger.app
    private let defaults: UserDefaults
    private weak var delegate: FirstLaunchHandlerDelegate?

    // MARK: - State

    /// Whether this is the first launch (user has never launched before).
    public var isFirstLaunch: Bool {
        !self.defaults.bool(forKey: Self.hasLaunchedKey)
    }

    /// Whether setup has been completed (OAuth configured and signed in).
    public var isSetupCompleted: Bool {
        self.defaults.bool(forKey: Self.setupCompletedKey)
    }

    /// Whether setup is required (first launch or setup not completed).
    public var isSetupRequired: Bool {
        self.isFirstLaunch || !self.isSetupCompleted
    }

    // MARK: - Initialization

    /// Creates a FirstLaunchHandler with the standard UserDefaults.
    public init() {
        self.defaults = .standard
    }

    /// Creates a FirstLaunchHandler with custom UserDefaults (for testing).
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Sets the delegate for receiving first launch events.
    public func setDelegate(_ delegate: FirstLaunchHandlerDelegate?) {
        self.delegate = delegate
    }

    /// Handles the first launch flow if this is the first launch.
    /// Should be called early in app startup.
    public func handleFirstLaunchIfNeeded() async {
        guard self.isFirstLaunch else {
            self.logger.debug("Not first launch, skipping first launch flow")
            return
        }

        self.logger.info("First launch detected, starting onboarding flow")

        // 1. Request notification permission
        if let delegate {
            let granted = await delegate.firstLaunchHandlerShouldRequestNotificationPermission(self)
            if !granted {
                self.logger.warning("Notification permission not granted during first launch")
            }
        }

        // 2. Enable launch at login by default
        self.enableLaunchAtLoginByDefault()

        // 3. Mark as launched (but setup not complete)
        self.markLaunched()

        // 4. Notify delegate that initial setup is complete
        await self.delegate?.firstLaunchHandlerDidCompleteInitialSetup(self)

        self.logger.info("First launch flow completed, awaiting OAuth setup")
    }

    /// Marks the app as having been launched before.
    public func markLaunched() {
        self.defaults.set(true, forKey: Self.hasLaunchedKey)
        self.logger.debug("Marked as launched")
    }

    /// Marks setup as completed (called after successful OAuth sign-in and sync).
    public func markSetupCompleted() {
        self.defaults.set(true, forKey: Self.setupCompletedKey)
        self.logger.info("Setup marked as completed")
    }

    /// Handles successful sign-in - enables all calendars and triggers sync.
    public func handleSuccessfulSignIn() async {
        self.logger.info("Handling successful sign-in")

        // Notify delegate to handle post-sign-in tasks
        await self.delegate?.firstLaunchHandlerDidSignIn(self)

        // Mark setup as completed
        self.markSetupCompleted()

        // Show success confirmation
        self.showSuccessConfirmation()
    }

    /// Resets first launch state (for testing or re-onboarding).
    public func resetFirstLaunchState() {
        self.defaults.removeObject(forKey: Self.hasLaunchedKey)
        self.defaults.removeObject(forKey: Self.setupCompletedKey)
        self.logger.info("First launch state reset")
    }

    // MARK: - Private Methods

    private func enableLaunchAtLoginByDefault() {
        let status = LaunchAtLoginManager.shared.setEnabled(true)
        if status.isEnabled {
            self.logger.debug("Enabled launch at login by default via SMAppService")
        } else {
            self.logger.warning("Failed to enable launch at login: \(status.description)")
        }
    }

    private func showSuccessConfirmation() {
        // Skip modal alerts during tests to prevent UI lockup
        guard !Self.isRunningTests else {
            self.logger.debug("Skipping success confirmation in test environment")
            return
        }

        let alert = NSAlert()
        alert.messageText = "You're all set!"
        alert.informativeText =
            "gcal-notifier will now monitor your calendar and alert you before meetings."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        self.logger.info("Displayed success confirmation")
    }
}
