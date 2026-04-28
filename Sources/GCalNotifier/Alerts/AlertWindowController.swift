import AppKit
import GCalNotifierCore
import OSLog
import SwiftUI

// MARK: - Alert Hosting View

/// Standard NSHostingView for alert content.
private class AlertHostingView<Content: View>: NSHostingView<Content> {}

// MARK: - Alert Window Actions

/// Actions that can be triggered from the alert window.
/// Used to communicate between AlertWindowController and its content view.
/// All actions are main-actor isolated for safe UI interactions.
@MainActor
public struct AlertWindowActions {
    public let onJoin: @MainActor () -> Void
    public let onSnooze: @MainActor (TimeInterval) -> Void
    public let onOpenCalendar: @MainActor () -> Void
    public let onDismiss: @MainActor () -> Void
    public let snoozeDurations: [TimeInterval]

    public init(
        onJoin: @escaping @MainActor () -> Void,
        onSnooze: @escaping @MainActor (TimeInterval) -> Void,
        onOpenCalendar: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void,
        snoozeDurations: [TimeInterval] = AlertSnoozePolicy.supportedDurations
    ) {
        self.onJoin = onJoin
        self.onSnooze = onSnooze
        self.onOpenCalendar = onOpenCalendar
        self.onDismiss = onDismiss
        self.snoozeDurations = snoozeDurations
    }
}

// MARK: - Alert Content Provider

/// Protocol for providing content to the alert window.
/// Implemented by AlertContentView to allow window controller to remain decoupled.
/// Main-actor isolated since it creates UI views.
@MainActor
public protocol AlertContentProvider {
    associatedtype ContentView: View

    func makeContentView(
        event: CalendarEvent,
        context: AlertContentContext,
        actions: AlertWindowActions
    ) -> ContentView
}

// MARK: - Default Placeholder Content

/// Placeholder content view until AlertContentView is implemented.
struct PlaceholderAlertContent: View {
    let event: CalendarEvent
    let stage: AlertStage
    let isSnoozed: Bool
    let snoozeContext: String?
    let actions: AlertWindowActions

    var body: some View {
        VStack(spacing: 16) {
            Text(self.stage == .stage1 ? "Meeting in 10 minutes" : "Meeting in 2 minutes")
                .font(.headline)

            Text(self.event.title)
                .font(.title2)

            Text(self.event.startTime.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if self.isSnoozed, let context = snoozeContext {
                Text("Snoozed from: \(context)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                if self.event.primaryMeetingURL != nil {
                    Button("Join") { self.actions.onJoin() }
                        .keyboardShortcut(.return, modifiers: [])
                }

                ForEach(self.actions.snoozeDurations, id: \.self) { duration in
                    Button("Snooze \(Int(duration / 60))m") { self.actions.onSnooze(duration) }
                }

                Button("Open Calendar") { self.actions.onOpenCalendar() }

                Button("Dismiss") { self.actions.onDismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(24)
        .frame(minWidth: 350, minHeight: 180)
    }
}

/// Default content provider using placeholder view.
public struct DefaultAlertContentProvider: AlertContentProvider {
    public init() {}

    public func makeContentView(
        event: CalendarEvent,
        context: AlertContentContext,
        actions: AlertWindowActions
    ) -> some View {
        AlertContentView(
            event: event,
            stage: context.stage,
            isSnoozed: context.isSnoozed,
            snoozeContext: context.snoozeContext,
            contextLine: context.contextLine,
            onJoin: actions.onJoin,
            onSnooze: actions.onSnooze,
            onOpenCalendar: actions.onOpenCalendar,
            onDismiss: actions.onDismiss,
            snoozeDurations: actions.snoozeDurations
        )
    }
}

// MARK: - AlertWindowController

/// NSPanel-based floating window controller for alert modals.
///
/// Features:
/// - Floats above other windows (NSPanel with .floating level)
/// - Visible on all Spaces (.canJoinAllSpaces)
/// - Works with full-screen apps (.fullScreenAuxiliary)
/// - Non-activating (doesn't steal focus)
/// - Keyboard shortcuts: Return to join, Escape to dismiss
@MainActor
public final class AlertWindowController: NSWindowController {
    // MARK: - State

    private var currentEvent: CalendarEvent?
    private var currentStage: AlertStage?
    private var alertEngine: AlertEngine?
    private var isSnoozing = false
    private var isCompletingAction = false
    private var urlOpener: @MainActor @Sendable (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    /// Detects if running in a test environment to avoid showing actual windows.
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

    // MARK: - Initialization

    public convenience init() {
        // Use a regular panel that activates normally - this ensures proper cursor
        // handling and standard window behavior. The panel will float above other
        // windows but activate when the user interacts with it.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )

        self.init(window: panel)
        self.configureWindow()
    }

    /// Initialize with a custom window (for testing).
    override public init(window: NSWindow?) {
        super.init(window: window)
        if window != nil {
            self.configureWindow()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    /// Sets the AlertEngine instance for handling snooze and acknowledge actions.
    public func setAlertEngine(_ engine: AlertEngine) {
        self.alertEngine = engine
    }

    public func setURLOpener(_ opener: @escaping @MainActor @Sendable (URL) -> Void) {
        self.urlOpener = opener
    }

    private func configureWindow() {
        guard let panel = window as? NSPanel else { return }

        // Floating above other windows
        panel.level = .floating

        // Visible on all Spaces and full-screen apps
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
        ]

        // Appearance
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        // Set delegate to handle window close button
        panel.delegate = self
    }

    private func positionWindow() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let windowFrame = window?.frame ?? .zero

        let xPos = screenFrame.midX - windowFrame.width / 2
        let yPos = screenFrame.minY + screenFrame.height * 0.6 // Upper-middle

        window?.setFrameOrigin(NSPoint(x: xPos, y: yPos))
    }
}

// MARK: - Show Alert

public extension AlertWindowController {
    /// Shows an alert for the given event and stage.
    ///
    /// - Parameters:
    ///   - event: The calendar event to show the alert for.
    ///   - stage: The alert stage (stage1 or stage2).
    ///   - snoozed: Whether this alert was snoozed.
    ///   - snoozeContext: Optional context about the snooze (e.g., original time).
    func showAlert(
        for event: CalendarEvent,
        stage: AlertStage,
        snoozed: Bool = false,
        snoozeContext: String? = nil,
        snoozeDurations: [TimeInterval] = AlertSnoozePolicy.supportedDurations,
        contextLine: String? = nil
    ) {
        self.currentEvent = event
        self.currentStage = stage

        let actions = AlertWindowActions(
            onJoin: { [weak self] in self?.joinMeeting() },
            onSnooze: { [weak self] duration in self?.snoozeMeeting(duration: duration) },
            onOpenCalendar: { [weak self] in self?.openInCalendar() },
            onDismiss: { [weak self] in self?.dismiss() },
            snoozeDurations: snoozeDurations
        )
        let context = AlertContentContext(
            stage: stage,
            isSnoozed: snoozed,
            snoozeContext: snoozeContext,
            contextLine: contextLine
        )

        // Create content view using default provider
        let provider = DefaultAlertContentProvider()
        let contentView = provider.makeContentView(
            event: event,
            context: context,
            actions: actions
        )

        let hostingView = AlertHostingView(rootView: contentView)
        window?.contentView = hostingView

        // Size to fit content
        window?.setContentSize(hostingView.fittingSize)

        // Skip showing actual window during tests to prevent UI lockups
        guard !Self.isRunningTests else {
            Logger.alerts.debug("Skipping window display in test environment")
            return
        }

        // Activate app (required for menu bar apps to show windows)
        NSApp.activate(ignoringOtherApps: true)

        // Show and bring to front
        self.positionWindow()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)

        Logger.alerts.info("Alert shown for event: \(event.id) stage: \(stage.rawValue)")
    }

    /// Shows an alert using a custom content provider.
    func showAlert(
        for event: CalendarEvent,
        stage: AlertStage,
        snoozed: Bool = false,
        snoozeContext: String? = nil,
        snoozeDurations: [TimeInterval] = AlertSnoozePolicy.supportedDurations,
        contextLine: String? = nil,
        contentProvider: some AlertContentProvider
    ) {
        self.currentEvent = event
        self.currentStage = stage

        let actions = AlertWindowActions(
            onJoin: { [weak self] in self?.joinMeeting() },
            onSnooze: { [weak self] duration in self?.snoozeMeeting(duration: duration) },
            onOpenCalendar: { [weak self] in self?.openInCalendar() },
            onDismiss: { [weak self] in self?.dismiss() },
            snoozeDurations: snoozeDurations
        )
        let context = AlertContentContext(
            stage: stage,
            isSnoozed: snoozed,
            snoozeContext: snoozeContext,
            contextLine: contextLine
        )

        let contentView = contentProvider.makeContentView(
            event: event,
            context: context,
            actions: actions
        )

        let hostingView = AlertHostingView(rootView: contentView)
        window?.contentView = hostingView

        // Size to fit content
        window?.setContentSize(hostingView.fittingSize)

        // Skip showing actual window during tests to prevent UI lockups
        guard !Self.isRunningTests else {
            Logger.alerts.debug("Skipping window display in test environment")
            return
        }

        // Activate app (required for menu bar apps to show windows)
        NSApp.activate(ignoringOtherApps: true)

        // Show and bring to front
        self.positionWindow()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)

        Logger.alerts.info("Alert shown for event: \(event.id) stage: \(stage.rawValue)")
    }
}

// MARK: - Actions

extension AlertWindowController {
    func joinMeeting() {
        guard let event = currentEvent,
              let stage = currentStage,
              let url = event.primaryMeetingURL
        else { return }

        let alertId = event.alertIdentifier(for: stage)
        self.urlOpener(url)
        Logger.alerts.info("Joining meeting: \(event.id)")
        self.completeCurrentAlert(.join(alertId: alertId)) { _ in }
    }

    func snoozeMeeting(duration: TimeInterval) {
        guard let event = currentEvent,
              let stage = currentStage,
              let engine = alertEngine
        else {
            Logger.alerts.warning("Cannot snooze: missing event, stage, or engine")
            return
        }

        let alertId = event.alertIdentifier(for: stage)

        Task { @MainActor in
            let result = await engine.handleAlertCommand(.snooze(alertId: alertId, duration: duration))
            if case .snoozed = result {
                Logger.alerts.info("Snoozed alert: \(alertId) for \(Int(duration / 60))m")
                self.isSnoozing = true
                close() // Close but don't acknowledge
            } else if case let .rejected(_, error) = result {
                Logger.alerts.error("Failed to snooze: \(error.localizedDescription)")
            }
        }
    }

    private func openInCalendar() {
        guard let event = currentEvent else { return }

        guard let url = event.htmlLink else {
            Logger.alerts.error("No calendar URL for event: \(event.id)")
            return
        }
        NSWorkspace.shared.open(url)
        Logger.alerts.info("Opening event in calendar: \(event.id)")
        // Don't close - user might want to come back
    }

    func dismiss() {
        guard let event = currentEvent,
              let stage = currentStage
        else {
            close()
            return
        }

        let alertId = event.alertIdentifier(for: stage)
        self.completeCurrentAlert(.dismiss(alertId: alertId)) { result in
            guard case .completed = result else { return }
            Logger.alerts.info("Dismissed alert \(stage.rawValue) for: \(event.id)")
        }
    }

    private func completeCurrentAlert(
        _ command: AlertCommand,
        completion: @escaping @MainActor (AlertCommandResult) -> Void
    ) {
        guard let engine = alertEngine else {
            close()
            return
        }

        self.isCompletingAction = true
        Task { @MainActor in
            let result = await engine.handleAlertCommand(command)
            completion(result)
            close()
        }
    }
}

// MARK: - NSWindowDelegate

extension AlertWindowController: NSWindowDelegate {
    public func windowWillClose(_: Notification) {
        // Acknowledge when window is closed via close button
        defer {
            self.isSnoozing = false
            self.isCompletingAction = false
        }

        guard !self.isSnoozing else { return }
        guard !self.isCompletingAction else { return }
        if let event = currentEvent, let stage = currentStage, let engine = alertEngine {
            let alertId = event.alertIdentifier(for: stage)
            Task {
                await engine.acknowledgeAlert(alertId: alertId, eventStartTime: event.startTime)
            }
        }
    }
}

// MARK: - Keyboard Support

public extension AlertWindowController {
    /// Handle Escape key to dismiss the alert.
    override func cancelOperation(_: Any?) {
        self.dismiss()
    }
}
