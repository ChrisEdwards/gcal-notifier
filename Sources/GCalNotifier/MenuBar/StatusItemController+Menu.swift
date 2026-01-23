import AppKit
import GCalNotifierCore

// MARK: - MenuBuilder

/// Builds NSMenu for the status item with pure logic, testable without live UI.
///
/// Follows a builder pattern to construct menu content from events and state,
/// separating logic from AppKit menu item creation.
public enum MenuBuilder {
    /// Menu item representation for testing and display logic.
    public enum MenuItem: Equatable, Sendable {
        case quickJoin(title: String, event: CalendarEvent)
        case conflictWarning(time: String, count: Int)
        case sectionHeader(title: String)
        case meeting(icon: String, title: String, time: String, event: CalendarEvent, enabled: Bool)
        case emptyState(message: String)
        case action(title: String, action: MenuAction)
        case separator
    }

    /// Actions that menu items can trigger.
    public enum MenuAction: Equatable, Sendable {
        case refresh
        case settings
        case quit
    }

    // MARK: - Public API

    /// Builds menu items from events and state.
    public static func buildMenuItems(
        events: [CalendarEvent],
        conflictingEventIds: Set<String>,
        now: Date = Date()
    ) -> [MenuItem] {
        var items: [MenuItem] = []

        let todaysEvents = Self.filterTodaysEvents(events, now: now)
        let nextMeeting = Self.findNextMeeting(from: todaysEvents, now: now)

        // Quick join section
        if let next = nextMeeting {
            items.append(.quickJoin(title: next.title, event: next))
            items.append(.separator)
        }

        // Conflict warning
        let conflicts = Self.findConflictingPairs(in: todaysEvents, conflictingIds: conflictingEventIds)
        if let firstConflict = conflicts.first {
            let timeString = Self.formatTime(firstConflict.startTime)
            items.append(.conflictWarning(time: timeString, count: conflicts.count))
            items.append(.separator)
        }

        // Today's meetings
        items.append(.sectionHeader(title: "Today's Meetings"))
        if todaysEvents.isEmpty {
            items.append(.emptyState(message: "No meetings today"))
        } else {
            for event in todaysEvents {
                let item = Self.makeMeetingItem(
                    event: event,
                    isConflicting: conflictingEventIds.contains(event.id)
                )
                items.append(item)
            }
        }
        items.append(.separator)

        // Actions
        items.append(.action(title: "Refresh Now", action: .refresh))
        items.append(.action(title: "Settings...", action: .settings))
        items.append(.separator)
        items.append(.action(title: "Quit gcal-notifier", action: .quit))

        return items
    }

    /// Formats the countdown string for display in quick join.
    public static func formatCountdown(to event: CalendarEvent, now: Date = Date()) -> String {
        StatusItemLogic.formatCountdown(secondsUntil: event.startTime.timeIntervalSince(now))
    }

    // MARK: - Private Helpers

    private static func filterTodaysEvents(_ events: [CalendarEvent], now: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        return events
            .filter { !$0.isAllDay }
            .filter { $0.startTime >= startOfDay && $0.startTime < endOfDay }
            .sorted { $0.startTime < $1.startTime }
    }

    private static func findNextMeeting(from events: [CalendarEvent], now: Date) -> CalendarEvent? {
        events
            .filter { $0.startTime > now && !$0.meetingLinks.isEmpty }
            .sorted { $0.startTime < $1.startTime }
            .first
    }

    private static func findConflictingPairs(
        in events: [CalendarEvent],
        conflictingIds: Set<String>
    ) -> [CalendarEvent] {
        events.filter { conflictingIds.contains($0.id) }
    }

    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func makeMeetingItem(event: CalendarEvent, isConflicting: Bool) -> MenuItem {
        let icon = if isConflicting {
            "!"
        } else if event.meetingLinks.isEmpty {
            "o"
        } else {
            "v"
        }

        let timeString = Self.formatTime(event.startTime)
        let truncatedTitle = String(event.title.prefix(25))

        return .meeting(
            icon: icon,
            title: truncatedTitle,
            time: timeString,
            event: event,
            enabled: !event.meetingLinks.isEmpty
        )
    }
}

// MARK: - MenuController

/// Creates and manages NSMenu instances from MenuBuilder output.
///
/// Handles the actual AppKit menu creation, keeping UI code separate from logic.
@MainActor
public final class MenuController: NSObject {
    // MARK: - State

    private var events: [CalendarEvent] = []
    private var conflictingEventIds: Set<String> = []

    // MARK: - Callbacks

    public var onJoinMeeting: ((CalendarEvent) -> Void)?
    public var onCopyLink: ((URL) -> Void)?
    public var onOpenInCalendar: ((CalendarEvent) -> Void)?
    public var onRefresh: (() -> Void)?
    public var onSettings: (() -> Void)?
    public var onQuit: (() -> Void)?

    // MARK: - Public API

    /// Updates the events to display.
    public func updateEvents(_ events: [CalendarEvent]) {
        self.events = events
    }

    /// Updates the set of conflicting event IDs.
    public func updateConflicts(_ conflictingIds: Set<String>) {
        self.conflictingEventIds = conflictingIds
    }

    /// Builds the menu from current state.
    public func buildMenu() -> NSMenu {
        let menuItems = MenuBuilder.buildMenuItems(
            events: self.events,
            conflictingEventIds: self.conflictingEventIds
        )
        return self.createMenu(from: menuItems)
    }

    // MARK: - Menu Creation

    private func createMenu(from items: [MenuBuilder.MenuItem]) -> NSMenu {
        let menu = NSMenu()

        for item in items {
            let nsItem = self.createNSMenuItem(from: item)
            menu.addItem(nsItem)
        }

        return menu
    }

    private func createNSMenuItem(from item: MenuBuilder.MenuItem) -> NSMenuItem {
        switch item {
        case let .quickJoin(title, event):
            self.createQuickJoinItem(title: title, event: event)

        case let .conflictWarning(time, count):
            self.createConflictWarningItem(time: time, count: count)

        case let .sectionHeader(title):
            self.createSectionHeader(title: title)

        case let .meeting(icon, title, time, event, enabled):
            self.createMeetingItem(icon: icon, title: title, time: time, event: event, enabled: enabled)

        case let .emptyState(message):
            self.createEmptyStateItem(message: message)

        case let .action(title, action):
            self.createActionItem(title: title, action: action)

        case .separator:
            .separator()
        }
    }

    private func createQuickJoinItem(title: String, event: CalendarEvent) -> NSMenuItem {
        let countdown = MenuBuilder.formatCountdown(to: event)
        let menuTitle = "> Join: \(title)    in \(countdown)"

        let item = NSMenuItem(title: menuTitle, action: #selector(handleJoinMeeting(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = event
        item.isEnabled = event.primaryMeetingURL != nil

        // Bold the "> Join:" part
        let attributed = NSMutableAttributedString(string: menuTitle)
        attributed.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: 13),
            range: NSRange(location: 0, length: 7)
        )
        item.attributedTitle = attributed

        return item
    }

    private func createConflictWarningItem(time: String, count: Int) -> NSMenuItem {
        let title = "! Conflict at \(time) (\(count) meetings)"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func createSectionHeader(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        return item
    }

    private func createMeetingItem(
        icon: String,
        title: String,
        time: String,
        event: CalendarEvent,
        enabled: Bool
    ) -> NSMenuItem {
        let menuTitle = "  \(icon) \(title)           \(time)"

        let item = NSMenuItem(
            title: menuTitle,
            action: #selector(handleEventClicked(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = event
        item.isEnabled = enabled

        // Add submenu for events with links
        if !event.meetingLinks.isEmpty {
            item.submenu = self.createEventSubmenu(event: event)
        }

        return item
    }

    private func createEmptyStateItem(message: String) -> NSMenuItem {
        let item = NSMenuItem(title: "  \(message)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func createActionItem(title: String, action: MenuBuilder.MenuAction) -> NSMenuItem {
        let selector = switch action {
        case .refresh:
            #selector(Self.handleRefresh(_:))
        case .settings:
            #selector(Self.handleSettings(_:))
        case .quit:
            #selector(Self.handleQuit(_:))
        }

        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func createEventSubmenu(event: CalendarEvent) -> NSMenu {
        let submenu = NSMenu()

        // Join Meeting
        if event.primaryMeetingURL != nil {
            let join = NSMenuItem(
                title: "Join Meeting",
                action: #selector(handleJoinMeeting(_:)),
                keyEquivalent: ""
            )
            join.target = self
            join.representedObject = event
            submenu.addItem(join)
        }

        // Copy Link
        if let url = event.primaryMeetingURL {
            let copy = NSMenuItem(
                title: "Copy Link",
                action: #selector(handleCopyLink(_:)),
                keyEquivalent: ""
            )
            copy.target = self
            copy.representedObject = url
            submenu.addItem(copy)
        }

        // Open in Calendar
        let openInCal = NSMenuItem(
            title: "Open in Calendar",
            action: #selector(handleOpenInCalendar(_:)),
            keyEquivalent: ""
        )
        openInCal.target = self
        openInCal.representedObject = event
        submenu.addItem(openInCal)

        return submenu
    }

    // MARK: - Action Handlers

    @objc private func handleJoinMeeting(_ sender: NSMenuItem) {
        guard let event = sender.representedObject as? CalendarEvent else { return }

        if let callback = onJoinMeeting {
            callback(event)
        } else if let url = event.primaryMeetingURL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func handleEventClicked(_ sender: NSMenuItem) {
        guard let event = sender.representedObject as? CalendarEvent else { return }

        if let callback = onJoinMeeting {
            callback(event)
        } else if let url = event.primaryMeetingURL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func handleCopyLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }

        if let callback = onCopyLink {
            callback(url)
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
    }

    @objc private func handleOpenInCalendar(_ sender: NSMenuItem) {
        guard let event = sender.representedObject as? CalendarEvent else { return }

        if let callback = onOpenInCalendar {
            callback(event)
        } else {
            // Construct Google Calendar event URL
            let urlString = "https://calendar.google.com/calendar/event?eid=\(event.id)"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func handleRefresh(_: NSMenuItem) {
        // Check if Option key is held for debug mode
        let optionHeld = NSEvent.modifierFlags.contains(.option)
        if optionHeld {
            UserDefaults.standard.set("debug", forKey: "logLevel")
        }

        self.onRefresh?()
    }

    @objc private func handleSettings(_: NSMenuItem) {
        if let callback = onSettings {
            callback()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    @objc private func handleQuit(_: NSMenuItem) {
        if let callback = onQuit {
            callback()
        } else {
            NSApp.terminate(nil)
        }
    }
}
