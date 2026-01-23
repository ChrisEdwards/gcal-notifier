import AppKit
import GCalNotifierCore

// MARK: - StatusItemState

/// Represents the visual state of the status item
public enum StatusItemState: Equatable, Sendable {
    case normal // 📅 - Next meeting countdown
    case alertWindow // 🔔 - Within alert window (< 10 min)
    case acknowledged // ✅ - Alert acknowledged
    case offline // ⚠️ - Offline or sync error
    case oauthNeeded // 🔑 - OAuth needed
}

// MARK: - StatusItemLogic

/// Result type for icon determination, containing the icon string and updated state.
public typealias IconResult = (icon: String, newState: StatusItemState)

/// Result type for display text generation, containing the text string and updated state.
public typealias DisplayResult = (text: String, newState: StatusItemState)

/// Pure logic functions for status item behavior, testable without AppKit.
public enum StatusItemLogic {
    /// Format a countdown string for display.
    public static func formatCountdown(secondsUntil interval: TimeInterval) -> String {
        if interval <= 0 {
            return "now"
        }

        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(totalMinutes)m"
        }
    }

    /// Calculate the appropriate update interval based on time until meeting.
    public static func calculateUpdateInterval(secondsUntilMeeting: TimeInterval?) -> TimeInterval {
        guard let timeUntil = secondsUntilMeeting else {
            return 5 * 60 // No meeting - every 5 min
        }

        switch timeUntil {
        case ...120: // <= 2 min
            return 10 // Every 10 sec
        case ...600: // <= 10 min
            return 30 // Every 30 sec
        case ...3600: // <= 60 min
            return 60 // Every minute
        default:
            return 5 * 60 // Every 5 min
        }
    }

    /// Find the next meeting from a list of events.
    public static func findNextMeeting(from events: [CalendarEvent], now: Date = Date()) -> CalendarEvent? {
        events
            .filter { !$0.isAllDay && $0.startTime > now }
            .sorted { $0.startTime < $1.startTime }
            .first
    }

    /// Determine the icon to display based on state and time until meeting.
    public static func determineIcon(state: StatusItemState, timeUntil: TimeInterval) -> IconResult {
        // Check for acknowledged state first
        if state == .acknowledged {
            return ("✅", state)
        }

        // Auto-transition to alert window when within 10 minutes
        if timeUntil <= 10 * 60, timeUntil > 0 {
            if state != .alertWindow, state != .acknowledged {
                return ("🔔", .alertWindow)
            }
            return (state == .acknowledged ? "✅" : "🔔", state)
        }

        // Normal state - reset from alert states if needed
        if state == .alertWindow || state == .acknowledged {
            return ("📅", .normal)
        }
        return ("📅", state)
    }

    /// Generate the display text for a given state and optional next meeting.
    public static func generateDisplayText(
        state: StatusItemState,
        nextMeeting: CalendarEvent?,
        now: Date = Date()
    ) -> DisplayResult {
        // Handle special states first
        switch state {
        case .offline:
            return ("⚠️ --", state)
        case .oauthNeeded:
            return ("🔑", state)
        case .normal, .alertWindow, .acknowledged:
            break
        }

        guard let next = nextMeeting else {
            return ("📅 --", state)
        }

        let timeUntil = next.startTime.timeIntervalSince(now)
        let countdown = self.formatCountdown(secondsUntil: timeUntil)
        let (icon, newState) = self.determineIcon(state: state, timeUntil: timeUntil)

        return ("\(icon) \(countdown)", newState)
    }
}

// MARK: - StatusItemController

/// Main controller for NSStatusItem with countdown display.
///
/// Manages the menu bar status item, displaying countdown to next meeting
/// with adaptive update intervals and state-based icons.
@MainActor
public final class StatusItemController: NSObject {
    // MARK: - UI

    private let statusItem: NSStatusItem
    private var menu: NSMenu?

    // MARK: - State

    private var currentText = ""
    private var updateTimer: Timer?
    private var events: [CalendarEvent] = []
    private var nextMeeting: CalendarEvent?
    private var state: StatusItemState = .normal

    // MARK: - Delegates

    public var onMenuWillOpen: (() -> NSMenu)?

    // MARK: - Initialization

    override public init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        self.setupStatusItem()
        startUpdateTimer()
    }

    /// Initialize with a custom status item (for testing)
    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()

        self.setupStatusItem()
        startUpdateTimer()
    }

    deinit {
        MainActor.assumeIsolated {
            updateTimer?.invalidate()
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        self.statusItem.button?.target = self
        self.statusItem.button?.action = #selector(statusItemClicked)
        self.statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Initial display
        updateStatusItemIfNeeded("📅 --")
    }

    // MARK: - Public API

    /// Update the events list and recalculate next meeting
    public func updateEvents(_ events: [CalendarEvent]) {
        self.events = events
        self.nextMeeting = StatusItemLogic.findNextMeeting(from: events)
        updateDisplay()
        scheduleNextUpdate()
    }

    /// Set the current state (for external state changes like offline/oauth)
    public func setState(_ newState: StatusItemState) {
        self.state = newState
        updateDisplay()
    }

    /// Mark the current alert as acknowledged
    public func acknowledgeAlert() {
        if self.state == .alertWindow {
            self.state = .acknowledged
            updateDisplay()
        }
    }

    /// Stop the update timer (for cleanup)
    public func stop() {
        self.updateTimer?.invalidate()
        self.updateTimer = nil
    }
}

// MARK: - Display Updates

extension StatusItemController {
    private func updateStatusItemIfNeeded(_ newText: String) {
        guard newText != self.currentText else { return }
        self.currentText = newText

        self.statusItem.button?.attributedTitle = NSAttributedString(
            string: newText,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            ]
        )
    }

    /// Update the status item display based on current state and next meeting
    public func updateDisplay() {
        let (text, newState) = StatusItemLogic.generateDisplayText(
            state: self.state,
            nextMeeting: self.nextMeeting
        )
        self.state = newState
        self.updateStatusItemIfNeeded(text)
    }
}

// MARK: - Timer Management

extension StatusItemController {
    private func startUpdateTimer() {
        self.scheduleNextUpdate()
    }

    private func scheduleNextUpdate() {
        self.updateTimer?.invalidate()

        let timeUntil = self.nextMeeting?.startTime.timeIntervalSinceNow
        let interval = StatusItemLogic.calculateUpdateInterval(secondsUntilMeeting: timeUntil)

        self.updateTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateDisplay()
                self?.scheduleNextUpdate()
            }
        }
    }
}

// MARK: - Menu Handling

extension StatusItemController {
    @objc private func statusItemClicked() {
        guard let menu = onMenuWillOpen?() else { return }
        self.menu = menu
        self.statusItem.menu = menu
        self.statusItem.button?.performClick(nil)
        self.statusItem.menu = nil // Allow click handler for next click
    }
}
