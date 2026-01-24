import AppKit
import CoreGraphics
import GCalNotifierCore
import OSLog

// MARK: - PresentationModeState

/// The current presentation mode state of the user.
public enum PresentationModeState: Sendable, Equatable {
    /// User is not presenting.
    case none
    /// User is sharing their screen.
    case screenSharing
    /// User has mirrored displays (e.g., projector).
    case displayMirrored
    /// Do Not Disturb is enabled.
    case doNotDisturb

    /// Whether alerts should be suppressed in this state.
    public var shouldSuppressAlerts: Bool {
        self != .none
    }

    /// A human-readable description of the state.
    public var description: String {
        switch self {
        case .none: "Normal"
        case .screenSharing: "Screen sharing"
        case .displayMirrored: "Display mirrored"
        case .doNotDisturb: "Do Not Disturb"
        }
    }
}

// MARK: - PresentationModeDetector

/// Detects when the user is in a presentation mode where alerts should be suppressed.
///
/// This detector checks for:
/// - Screen sharing/recording activity
/// - Mirrored displays (presenting to projector)
/// - Do Not Disturb mode (best effort, limited API access)
///
/// ## Usage
/// ```swift
/// let detector = PresentationModeDetector.shared
/// let state = await detector.detect()
///
/// if state.shouldSuppressAlerts {
///     // Show notification banner instead of modal
/// }
/// ```
@MainActor
public final class PresentationModeDetector {
    // MARK: - Singleton

    public static let shared = PresentationModeDetector()

    // MARK: - Dependencies

    private let logger = Logger.app

    // MARK: - Initialization

    private init() {}

    // MARK: - Detection

    /// Detects the current presentation mode state.
    ///
    /// Checks in order of priority:
    /// 1. Screen sharing/recording
    /// 2. Display mirroring
    /// 3. Do Not Disturb
    ///
    /// Returns the first detected state, or `.none` if not presenting.
    public func detect() -> PresentationModeState {
        // Check for display mirroring (most reliable detection)
        if self.isDisplayMirrored() {
            self.logger.debug("Detected mirrored display")
            return .displayMirrored
        }

        // Check for screen recording indicator
        if self.isScreenRecordingIndicatorVisible() {
            self.logger.debug("Detected screen recording indicator")
            return .screenSharing
        }

        // Check for DND (best effort)
        if self.isDNDEnabled() {
            self.logger.debug("Detected Do Not Disturb mode")
            return .doNotDisturb
        }

        return .none
    }

    /// Convenience method to check if alerts should be suppressed.
    public func shouldSuppressAlerts(settings: SettingsStore) -> Bool {
        guard settings.suppressDuringScreenShare else { return false }
        return self.detect().shouldSuppressAlerts
    }

    // MARK: - Display Mirroring Detection

    /// Checks if any display is mirrored (presenting to a projector or external display).
    private func isDisplayMirrored() -> Bool {
        // Get all active displays
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)

        guard displayCount > 0 else { return false }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)

        // Check if any display is in a mirror set
        return displays.contains { CGDisplayIsInMirrorSet($0) != 0 }
    }

    // MARK: - Screen Recording Detection

    /// Checks if the screen recording indicator is visible in the menu bar.
    ///
    /// macOS shows a recording indicator when screen capture is active.
    /// We detect this by checking for the presence of the system screen recording window.
    private func isScreenRecordingIndicatorVisible() -> Bool {
        // Check if there's a screen recording session active by looking for
        // the characteristic window that macOS creates during screen capture.
        // This is a heuristic approach since there's no direct API.

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

        for window in windowList {
            // Check for SystemUIServer windows which include the recording indicator
            guard let ownerName = window[kCGWindowOwnerName as String] as? String else {
                continue
            }

            // The screen recording indicator is owned by Control Center or SystemUIServer
            // and has specific characteristics
            if ownerName == "Control Center" || ownerName == "SystemUIServer" {
                if let windowName = window[kCGWindowName as String] as? String {
                    // Recording indicator has specific naming patterns
                    if windowName.contains("Recording") || windowName.contains("Screen Capture") {
                        return true
                    }
                }
            }

            // Check for active screen sharing applications with overlay windows
            let screenSharingApps = ["zoom.us", "Slack", "Microsoft Teams", "Google Chrome", "FaceTime"]
            let ownerLower = ownerName.lowercased()
            let hasOverlayFromSharingApp = screenSharingApps.contains { app in
                guard ownerLower.contains(app.lowercased()) else { return false }
                // Check if the app has an overlay window (sharing indicator)
                guard let layer = window[kCGWindowLayer as String] as? Int else { return false }
                return layer >= 25 // High layer windows are typically overlays/sharing indicators
            }
            if hasOverlayFromSharingApp {
                return true
            }
        }

        return false
    }

    // MARK: - Do Not Disturb Detection

    /// Checks if Do Not Disturb is enabled.
    ///
    /// Apple does not provide a public API for DND status, so this uses
    /// indirect detection methods which may not be 100% reliable.
    private func isDNDEnabled() -> Bool {
        // macOS Monterey+ stores Focus mode state in UserDefaults
        // This is not a public API and may change in future macOS versions
        let notificationCenterDefaults = UserDefaults(suiteName: "com.apple.notificationcenterui")

        // Check for the older DND preference
        if notificationCenterDefaults?.bool(forKey: "doNotDisturb") == true {
            return true
        }

        // Check for Focus mode (macOS 12+)
        // The actual implementation would need to use private APIs or
        // heuristics since Apple doesn't expose Focus state publicly.

        // Alternative: Check if notifications are currently being suppressed
        // by looking at the notification center's behavior
        // This is a best-effort detection that may not catch all cases

        return false
    }
}

// MARK: - AlertDelivery Extension for Suppression

/// Extension to convert PresentationModeState to AlertDowngradeReason.
public extension PresentationModeState {
    /// Converts the presentation mode state to an alert downgrade reason.
    var alertDowngradeReason: AlertDowngradeReason? {
        switch self {
        case .none:
            nil
        case .screenSharing, .displayMirrored:
            .screenSharing
        case .doNotDisturb:
            .doNotDisturb
        }
    }
}
