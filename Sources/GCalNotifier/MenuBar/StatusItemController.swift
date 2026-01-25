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
    /// Uses ceiling so "12m 30s left" shows as "13m" not "12m".
    public static func formatCountdown(secondsUntil interval: TimeInterval) -> String {
        if interval <= 0 {
            return "now"
        }

        // Round up - if there's any partial minute, count it as a full minute
        let totalMinutes = Int(ceil(interval / 60))
        let hours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(totalMinutes)m"
        }
    }

    /// Format back-to-back countdown string showing both current meeting end and next meeting start.
    /// Format: "12m → 5m" (current ends in 12m, next starts in 5m)
    public static func formatBackToBackCountdown(
        currentEndsIn: TimeInterval,
        nextStartsIn: TimeInterval
    ) -> String {
        let currentMinutes = max(0, Int(currentEndsIn / 60))
        let nextMinutes = max(0, Int(nextStartsIn / 60))
        return "\(currentMinutes)m → \(nextMinutes)m"
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

    /// Generate the display text for a back-to-back meeting situation.
    /// Shows dual countdown: current meeting end time → next meeting start time
    public static func generateBackToBackDisplayText(
        state: StatusItemState,
        backToBackState: BackToBackState,
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

        // If not in a back-to-back situation, fall back to normal display
        guard backToBackState.isBackToBack,
              let current = backToBackState.currentMeeting,
              let next = backToBackState.nextBackToBackMeeting
        else {
            return ("📅 --", state)
        }

        let currentEndsIn = current.endTime.timeIntervalSince(now)
        let nextStartsIn = next.startTime.timeIntervalSince(now)

        let countdown = self.formatBackToBackCountdown(currentEndsIn: currentEndsIn, nextStartsIn: nextStartsIn)
        return ("📅 \(countdown)", state)
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

    // MARK: - Data Source

    private var eventCache: EventCache?

    // MARK: - State

    private var currentText = ""
    private var updateTimer: Timer?
    private var events: [CalendarEvent] = []
    private var nextMeeting: CalendarEvent?
    private var state: StatusItemState = .normal
    private var backToBackState: BackToBackState = .none

    // MARK: - Delegates

    /// Called asynchronously before building the menu, for loading data.
    public var onMenuWillPrepare: (() async -> Void)?

    /// Called synchronously to build and return the menu.
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

    // MARK: - Configuration

    /// Configure the controller with an EventCache to load events from.
    /// Call this after initialization to enable automatic event loading.
    public func configure(eventCache: EventCache) {
        self.eventCache = eventCache

        // Load events immediately from cache
        Task {
            await self.loadEventsFromCache()
        }
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

    /// Update the events list and recalculate next meeting and back-to-back state
    public func updateEvents(_ events: [CalendarEvent]) {
        self.events = events
        self.nextMeeting = StatusItemLogic.findNextMeeting(from: events)
        self.backToBackState = BackToBackState.detect(from: events)
        updateDisplay()
        scheduleNextUpdate()
    }

    /// Update the back-to-back state explicitly (for external updates)
    public func updateBackToBackState(_ state: BackToBackState) {
        self.backToBackState = state
        updateDisplay()
    }

    /// Get the current back-to-back state
    public var currentBackToBackState: BackToBackState {
        self.backToBackState
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
        self.pulseTimer?.invalidate()
        self.pulseTimer = nil
    }

    // MARK: - Pulse Animation for Suppressed Alerts

    private var pulseCount = 0
    private let maxPulseCount = 6 // 3 on, 3 off cycles
    private var pulseTimer: Timer?

    /// Pulses the menu bar icon to indicate a suppressed alert.
    ///
    /// When an alert is suppressed (due to screen sharing, DND, etc.),
    /// we pulse the menu bar icon to draw attention without showing a modal.
    public func pulseIcon() {
        self.pulseCount = 0
        self.pulseIconAnimation()
    }

    private func pulseIconAnimation() {
        self.pulseTimer?.invalidate()

        self.pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                self.pulseCount += 1

                if self.pulseCount > self.maxPulseCount {
                    self.pulseTimer?.invalidate()
                    self.pulseTimer = nil
                    self.updateDisplay() // Restore normal display
                    return
                }

                // Alternate between alert icon and current state
                if self.pulseCount.isMultiple(of: 2) {
                    self.updateDisplay()
                } else {
                    self.updateStatusItemIfNeeded("🔔")
                }
            }
        }
    }

    /// Shows a badge indicator on the menu bar for a suppressed alert.
    ///
    /// Uses a different icon to indicate there's a pending alert that was suppressed.
    public func showSuppressedBadge() {
        let countdown = StatusItemLogic.formatCountdown(
            secondsUntil: self.nextMeeting?.startTime.timeIntervalSinceNow ?? 0
        )
        self.updateStatusItemIfNeeded("📵 \(countdown)")
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
        // Use back-to-back display if user is in a back-to-back situation
        if self.backToBackState.isBackToBack {
            let (text, newState) = StatusItemLogic.generateBackToBackDisplayText(
                state: self.state,
                backToBackState: self.backToBackState
            )
            self.state = newState
            self.updateStatusItemIfNeeded(text)
        } else {
            let (text, newState) = StatusItemLogic.generateDisplayText(
                state: self.state,
                nextMeeting: self.nextMeeting
            )
            self.state = newState
            self.updateStatusItemIfNeeded(text)
        }
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
                // Reload from cache on each tick to pick up sync changes
                await self?.loadEventsFromCache()
                self?.scheduleNextUpdate()
            }
        }
    }

    /// Load events from the configured EventCache and update the display.
    /// Called automatically on timer ticks when EventCache is configured.
    public func loadEventsFromCache() async {
        guard let eventCache else { return }

        do {
            let cachedEvents = try await eventCache.load()
            self.updateEvents(cachedEvents)
        } catch {
            // Cache load failed - keep existing events, don't clear display
            // The display will show stale data until next successful load
        }
    }
}

// MARK: - Menu Handling

extension StatusItemController {
    @objc private func statusItemClicked() {
        Task {
            // Allow async preparation (e.g., loading events from cache)
            await self.onMenuWillPrepare?()

            // Build and show the menu
            guard let menu = self.onMenuWillOpen?() else { return }
            self.menu = menu
            self.statusItem.menu = menu
            self.statusItem.button?.performClick(nil)
            self.statusItem.menu = nil // Allow click handler for next click
        }
    }
}
