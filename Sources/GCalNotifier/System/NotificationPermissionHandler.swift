import AppKit
import Foundation
import GCalNotifierCore
import OSLog

// MARK: - NotificationPermissionHandlerDelegate

/// Delegate protocol for receiving permission status change notifications.
public protocol NotificationPermissionHandlerDelegate: AnyObject, Sendable {
    /// Called when the notification permission status changes.
    func permissionStatusDidChange(_ handler: NotificationPermissionHandler, isGranted: Bool) async
}

// MARK: - NotificationPermissionHandler

/// Monitors and manages notification permission state.
///
/// This handler:
/// 1. Checks the current notification permission status
/// 2. Notifies delegates when permission state changes
/// 3. Provides functionality to open System Settings for notifications
///
/// ## Usage
/// ```swift
/// let handler = NotificationPermissionHandler()
/// await handler.checkPermission()
/// if handler.permissionDenied {
///     // Show warning in menu
/// }
/// ```
@MainActor
public final class NotificationPermissionHandler {
    // MARK: - Constants

    /// Interval between automatic permission checks (5 minutes).
    private static let checkInterval: TimeInterval = 5 * 60

    // MARK: - Dependencies

    private let logger = Logger.app
    private let notificationCenter: any NotificationCenterProtocol
    private weak var delegate: NotificationPermissionHandlerDelegate?

    // MARK: - State

    /// Current notification authorization status.
    public private(set) var authorizationStatus: NotificationAuthorizationStatus = .notDetermined

    /// Whether notification permission has been denied by the user.
    public var permissionDenied: Bool {
        self.authorizationStatus == .denied
    }

    /// Whether notifications are authorized.
    public var isAuthorized: Bool {
        self.authorizationStatus == .authorized || self.authorizationStatus == .provisional
    }

    /// Whether permission has not been determined yet.
    public var isNotDetermined: Bool {
        self.authorizationStatus == .notDetermined
    }

    private var checkTimer: Timer?
    private var isMonitoring = false

    // MARK: - Initialization

    /// Creates a handler with the default system notification center.
    public init() {
        self.notificationCenter = SystemNotificationCenter()
    }

    /// Creates a handler with a custom notification center (for testing).
    public init(notificationCenter: any NotificationCenterProtocol) {
        self.notificationCenter = notificationCenter
    }

    // MARK: - Public API

    /// Sets the delegate for receiving permission status changes.
    public func setDelegate(_ delegate: NotificationPermissionHandlerDelegate?) {
        self.delegate = delegate
    }

    /// Checks the current notification permission status.
    /// Returns the authorization status and updates internal state.
    @discardableResult
    public func checkPermission() async -> NotificationAuthorizationStatus {
        let previousStatus = self.authorizationStatus
        self.authorizationStatus = await self.notificationCenter.notificationSettings()

        self.logger.debug("Notification permission status: \(String(describing: self.authorizationStatus))")

        // Notify delegate if status changed
        if previousStatus != self.authorizationStatus {
            let isGranted = self.isAuthorized
            await self.delegate?.permissionStatusDidChange(self, isGranted: isGranted)
        }

        return self.authorizationStatus
    }

    /// Requests notification authorization from the user.
    /// Returns true if authorization was granted.
    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await self.notificationCenter.requestAuthorization(options: [.alert, .sound])
            await self.checkPermission()
            return granted
        } catch {
            self.logger.error("Failed to request notification authorization: \(error)")
            await self.checkPermission()
            return false
        }
    }

    /// Starts periodic permission monitoring.
    /// Checks permission every 5 minutes to detect changes.
    public func startMonitoring() {
        guard !self.isMonitoring else {
            self.logger.debug("NotificationPermissionHandler already monitoring")
            return
        }

        self.isMonitoring = true

        // Initial check
        Task {
            await self.checkPermission()
        }

        // Schedule periodic checks
        self.checkTimer = Timer.scheduledTimer(
            withTimeInterval: Self.checkInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkPermission()
            }
        }

        self.logger.info("NotificationPermissionHandler started monitoring")
    }

    /// Stops periodic permission monitoring.
    public func stopMonitoring() {
        guard self.isMonitoring else { return }

        self.isMonitoring = false
        self.checkTimer?.invalidate()
        self.checkTimer = nil
        self.logger.info("NotificationPermissionHandler stopped monitoring")
    }

    /// Opens System Settings to the notification preferences for this app.
    public func openNotificationSettings() {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            self.logger.error("Failed to get bundle identifier")
            return
        }

        // macOS 13+ uses System Settings, older versions use System Preferences
        // The URL scheme opens the Notifications pane for the specific app
        let urlString = "x-apple.systempreferences:com.apple.preference.notifications?\(bundleId)"

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            self.logger.info("Opened notification settings for app")
        } else {
            // Fallback: open general notification settings
            if let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(fallbackURL)
                self.logger.info("Opened general notification settings")
            }
        }
    }
}
