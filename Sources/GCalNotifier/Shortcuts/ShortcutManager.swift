import AppKit
import GCalNotifierCore
import KeyboardShortcuts
import OSLog

// MARK: - Shortcut Names

extension KeyboardShortcuts.Name {
    /// Shortcut to instantly join the next upcoming meeting with a video link.
    static let joinNextMeeting = Self("joinNextMeeting", default: .init(.j, modifiers: [.command, .shift]))

    /// Shortcut to dismiss the currently visible alert window.
    static let dismissAlert = Self("dismissAlert", default: .init(.d, modifiers: [.command, .shift]))
}

// MARK: - ShortcutManager

/// Manages global keyboard shortcuts for quick meeting actions.
///
/// Default shortcuts:
/// - `Cmd+Shift+J`: Join next meeting
/// - `Cmd+Shift+D`: Dismiss current alert
///
/// Shortcuts can be customized in Preferences > Shortcuts.
@MainActor
public final class ShortcutManager {
    // MARK: - Singleton

    /// Shared instance of the ShortcutManager.
    public static let shared = ShortcutManager()

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

    private var eventCache: EventCache?
    private var alertWindowController: AlertWindowController?
    private var settings: SettingsStore?

    // MARK: - State

    private var isSetUp = false

    // MARK: - Initialization

    private init() {}

    // MARK: - Configuration

    /// Configures the ShortcutManager with required dependencies.
    ///
    /// - Parameters:
    ///   - eventCache: The event cache for looking up the next meeting.
    ///   - alertWindowController: The alert window controller for dismissing alerts.
    ///   - settings: The settings store for checking if shortcuts are enabled.
    public func configure(
        eventCache: EventCache,
        alertWindowController: AlertWindowController,
        settings: SettingsStore
    ) {
        self.eventCache = eventCache
        self.alertWindowController = alertWindowController
        self.settings = settings
    }

    // MARK: - Setup

    /// Sets up global keyboard shortcuts. Should be called after app launch.
    ///
    /// Registers handlers for:
    /// - Join next meeting (Cmd+Shift+J by default)
    /// - Dismiss alert (Cmd+Shift+D by default)
    public func setup() {
        guard !self.isSetUp else { return }
        self.isSetUp = true

        KeyboardShortcuts.onKeyDown(for: .joinNextMeeting) { [weak self] in
            Task { @MainActor in
                self?.handleJoinShortcut()
            }
        }

        KeyboardShortcuts.onKeyDown(for: .dismissAlert) { [weak self] in
            Task { @MainActor in
                self?.handleDismissShortcut()
            }
        }

        Logger.shortcuts.info("Global keyboard shortcuts registered")
    }

    /// Removes all keyboard shortcut handlers.
    public func teardown() {
        KeyboardShortcuts.removeAllHandlers()
        self.isSetUp = false
        Logger.shortcuts.info("Global keyboard shortcuts removed")
    }

    // MARK: - Shortcut Handlers

    private func handleJoinShortcut() {
        guard self.settings?.shortcutsEnabled ?? true else {
            Logger.shortcuts.debug("Shortcuts disabled, ignoring join shortcut")
            return
        }

        Task { @MainActor in
            await self.joinNextMeeting()
        }
    }

    private func handleDismissShortcut() {
        guard self.settings?.shortcutsEnabled ?? true else {
            Logger.shortcuts.debug("Shortcuts disabled, ignoring dismiss shortcut")
            return
        }

        self.dismissCurrentAlert()
    }

    // MARK: - Join Next Meeting

    private func joinNextMeeting() async {
        guard let eventCache else {
            Logger.shortcuts.warning("EventCache not configured, cannot join meeting")
            self.showNotification(title: "Shortcut Error", body: "Calendar not configured")
            return
        }

        do {
            guard let nextMeeting = try await findNextMeetingWithVideoLink(in: eventCache) else {
                self.showNotification(
                    title: "No Upcoming Meetings",
                    body: "No meetings with video links in the next 24 hours"
                )
                Logger.shortcuts.info("Join shortcut: No upcoming meetings with video links")
                return
            }

            let timeUntilMeeting = nextMeeting.startTime.timeIntervalSinceNow

            if timeUntilMeeting <= 30 * 60 {
                // Within 30 minutes - join directly
                self.joinMeeting(nextMeeting)
            } else {
                // Far away - show confirmation
                self.showJoinConfirmation(for: nextMeeting)
            }
        } catch {
            Logger.shortcuts.error("Failed to find next meeting: \(error.localizedDescription)")
            self.showNotification(title: "Error", body: "Failed to check calendar")
        }
    }

    private func findNextMeetingWithVideoLink(in cache: EventCache) async throws -> CalendarEvent? {
        let now = Date()
        let endOfDay = now.addingTimeInterval(24 * 60 * 60)

        let events = try await cache.events(from: now, to: endOfDay)
        return events
            .filter { $0.hasVideoLink && $0.startTime > now }
            .sorted { $0.startTime < $1.startTime }
            .first
    }

    private func joinMeeting(_ meeting: CalendarEvent) {
        guard let url = meeting.primaryMeetingURL else {
            Logger.shortcuts.warning("Meeting has no video URL: \(meeting.id)")
            return
        }

        NSWorkspace.shared.open(url)
        Logger.shortcuts.info("Joined meeting via shortcut: \(meeting.title)")
    }

    private func showJoinConfirmation(for meeting: CalendarEvent) {
        // Skip modal alerts during tests to prevent UI lockup
        guard !Self.isRunningTests else {
            Logger.shortcuts.debug("Skipping join confirmation in test environment")
            return
        }

        let timeUntil = self.formatTimeUntil(meeting.startTime)

        let alert = NSAlert()
        alert.messageText = "Join meeting in \(timeUntil)?"
        alert.informativeText = meeting.title
        alert.addButton(withTitle: "Join Now")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            self.joinMeeting(meeting)
        }
    }

    private func formatTimeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            if remainingMinutes > 0 {
                return "\(hours)h \(remainingMinutes)m"
            }
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    // MARK: - Dismiss Alert

    private func dismissCurrentAlert() {
        // Find visible alert window
        let alertWindow = NSApp.windows.first { window in
            window is NSPanel && window.isVisible && window.level == .floating
        }

        guard let window = alertWindow else {
            Logger.shortcuts.debug("Dismiss shortcut: No alert window visible")
            return
        }

        // Close the window - the window delegate will handle acknowledgment
        window.close()
        Logger.shortcuts.info("Dismissed alert via shortcut")
    }

    // MARK: - Notifications

    private func showNotification(title: String, body: String) {
        // Create a brief HUD-style notification using the standard notification system
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = nil

        // Use the deprecated API for simple one-off notifications
        // This is acceptable for quick feedback that doesn't need UNUserNotificationCenter complexity
        NSUserNotificationCenter.default.deliver(notification)
    }
}

// MARK: - Logger Extension

extension Logger {
    static let shortcuts = Logger(subsystem: Bundle.main.bundleIdentifier ?? "gcal-notifier", category: "Shortcuts")
}
