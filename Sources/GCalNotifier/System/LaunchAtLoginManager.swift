import AppKit
import Foundation
import GCalNotifierCore
import OSLog
import ServiceManagement

// MARK: - LaunchAtLoginStatus

/// Status of launch-at-login registration with the system.
public enum LaunchAtLoginStatus: Sendable {
    case enabled
    case disabled
    case requiresApproval
    case error(String)

    public var description: String {
        switch self {
        case .enabled: "Will launch at login"
        case .disabled: "Will not launch at login"
        case .requiresApproval: "Requires approval in System Settings"
        case let .error(msg): "Error: \(msg)"
        }
    }

    public var isEnabled: Bool {
        if case .enabled = self { return true }
        return false
    }
}

// MARK: - LaunchAtLoginManager

/// Manages launch-at-login functionality using SMAppService.
///
/// Uses the modern SMAppService API (macOS 13+) which:
/// - Requires no helper apps
/// - Is managed by the system
/// - Appears in System Settings → General → Login Items
///
/// ## Usage
/// ```swift
/// // Check status
/// let status = LaunchAtLoginManager.shared.checkStatus()
///
/// // Enable/disable
/// LaunchAtLoginManager.shared.setEnabled(true)
///
/// // Use in SwiftUI
/// Toggle("Launch at login", isOn: LaunchAtLoginManager.shared.isEnabledBinding)
/// ```
@MainActor
public final class LaunchAtLoginManager {
    // MARK: - Singleton

    public static let shared = LaunchAtLoginManager()

    // MARK: - Dependencies

    private let logger = Logger.app

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Whether launch-at-login is currently enabled.
    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Sets the launch-at-login state.
    /// - Parameter enabled: Whether to enable or disable launch at login.
    /// - Returns: The resulting status after the operation.
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> LaunchAtLoginStatus {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                self.logger.info("Enabled launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                self.logger.info("Disabled launch at login")
            }
            return self.checkStatus()
        } catch {
            self.logger.error("Failed to set launch at login: \(error.localizedDescription)")
            return .error(error.localizedDescription)
        }
    }

    /// Checks the current launch-at-login status.
    public func checkStatus() -> LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .error("App not found in login items")
        @unknown default:
            return .error("Unknown status")
        }
    }

    /// Opens System Settings to the Login Items pane.
    /// Useful when the status is `.requiresApproval`.
    public func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            self.logger.error("Failed to create Login Items settings URL")
            return
        }
        NSWorkspace.shared.open(url)
        self.logger.info("Opened Login Items settings")
    }
}
