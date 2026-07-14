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

/// Default content provider using the standard alert view.
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
/// - Requires deliberate button or close-button acknowledgement
@MainActor
public final class AlertWindowController: NSWindowController {
    // MARK: - State

    private static let visibilityGracePeriod: TimeInterval = 5 * 60
    private static let visibilityCheckInterval: TimeInterval = 20
    private var currentEvent: CalendarEvent?
    private var currentStage: AlertStage?
    private var alertEngine: AlertEngine?
    private var isClosingWithoutAcknowledgment = false
    private var isCompletingAction = false
    private var visibilityTask: Task<Void, Never>?
    private var windowClosedHandler: (() -> Void)?
    private(set) var alertStackIndex = 0
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
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled, .closable, .nonactivatingPanel],
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

    deinit {
        self.visibilityTask?.cancel()
    }

    // MARK: - Configuration

    /// Sets the AlertEngine instance for handling snooze and acknowledge actions.
    public func setAlertEngine(_ engine: AlertEngine) {
        self.alertEngine = engine
    }

    public func setURLOpener(_ opener: @escaping @MainActor @Sendable (URL) -> Void) {
        self.urlOpener = opener
    }

    func setWindowClosedHandler(_ handler: @escaping () -> Void) {
        self.windowClosedHandler = handler
    }

    func setAlertStackIndex(_ index: Int) {
        self.alertStackIndex = max(0, index)
        if window?.isVisible == true {
            self.positionWindow()
        }
    }

    private func configureWindow() {
        guard let panel = window as? NSPanel else { return }

        // Floating above other windows
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

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
        let firstWindowY = screenFrame.minY + screenFrame.height * 0.6
        let stackOffset = CGFloat(self.alertStackIndex) * (windowFrame.height + 12)
        let yPos = max(screenFrame.minY, firstWindowY - stackOffset)

        window?.setFrameOrigin(NSPoint(x: xPos, y: yPos))
    }

    private func present() -> Bool {
        guard !Self.isRunningTests else {
            Logger.alerts.debug("Skipping window display in test environment")
            return false
        }

        self.positionWindow()
        window?.orderFrontRegardless()
        return true
    }

    func maintainAlertVisibility(at date: Date) {
        guard let event = currentEvent else {
            self.stopVisibilityWatchdog()
            return
        }
        guard date < event.startTime.addingTimeInterval(Self.visibilityGracePeriod) else {
            self.isClosingWithoutAcknowledgment = true
            self.stopVisibilityWatchdog()
            window?.close()
            return
        }
        guard window?.isVisible == false else { return }
        window?.orderFrontRegardless()
    }

    private func startVisibilityWatchdog() {
        self.stopVisibilityWatchdog()
        guard !Self.isRunningTests, self.currentEvent != nil else { return }

        self.visibilityTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.visibilityCheckInterval))
                } catch {
                    return
                }
                guard let self else { return }
                self.maintainAlertVisibility(at: Date())
            }
        }
    }

    private func stopVisibilityWatchdog() {
        self.visibilityTask?.cancel()
        self.visibilityTask = nil
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
        self.showAlert(
            for: event,
            stage: stage,
            snoozed: snoozed,
            snoozeContext: snoozeContext,
            snoozeDurations: snoozeDurations,
            contextLine: contextLine,
            contentProvider: DefaultAlertContentProvider()
        )
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

        if self.present() {
            Logger.alerts.info("Alert shown for event: \(event.id) stage: \(stage.rawValue)")
        }
        self.startVisibilityWatchdog()
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
                self.stopVisibilityWatchdog()
                self.isClosingWithoutAcknowledgment = true
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
        self.stopVisibilityWatchdog()
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
        self.stopVisibilityWatchdog()
        // Acknowledge when window is closed via close button
        defer {
            self.isClosingWithoutAcknowledgment = false
            self.isCompletingAction = false
            self.currentEvent = nil
            self.currentStage = nil
            self.windowClosedHandler?()
        }

        guard !self.isClosingWithoutAcknowledgment else { return }
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
    /// Escape intentionally does nothing so a keystroke cannot acknowledge an alert.
    override func cancelOperation(_: Any?) {}
}
