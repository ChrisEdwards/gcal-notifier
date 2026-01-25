import AppKit
import GCalNotifierCore

// MARK: - MenuController

/// Creates and manages NSMenu instances from MenuBuilder output.
///
/// Handles the actual AppKit menu creation, keeping UI code separate from logic.
@MainActor
public final class MenuController: NSObject {
    // MARK: - Dependencies

    private var eventCache: EventCache?

    // MARK: - State

    private var events: [CalendarEvent] = []
    private var conflictingEventIds: Set<String> = []
    private var notificationPermissionDenied: Bool = false
    private var setupRequired: Bool = false

    // MARK: - Callbacks

    public var onJoinMeeting: ((CalendarEvent) -> Void)?
    public var onCopyLink: ((URL) -> Void)?
    public var onOpenInCalendar: ((CalendarEvent) -> Void)?
    public var onRefresh: (() -> Void)?
    public var onSettings: (() -> Void)?
    public var onQuit: (() -> Void)?
    public var onOpenNotificationSettings: (() -> Void)?

    // MARK: - Configuration

    /// Configures the menu controller with its dependencies.
    /// - Parameter eventCache: The event cache to load events from.
    public func configure(eventCache: EventCache) {
        self.eventCache = eventCache
    }

    // MARK: - Public API

    /// Loads today's events from the event cache.
    /// Call this before building the menu to ensure fresh data.
    public func loadEventsFromCache() async {
        guard let eventCache else { return }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        do {
            let todaysEvents = try await eventCache.events(from: startOfDay, to: endOfDay)
            self.events = todaysEvents
        } catch {
            // Log error but continue with existing events
            // Menu will show whatever state it had before
        }
    }

    /// Updates the events to display.
    public func updateEvents(_ events: [CalendarEvent]) {
        self.events = events
    }

    /// Updates the set of conflicting event IDs.
    public func updateConflicts(_ conflictingIds: Set<String>) {
        self.conflictingEventIds = conflictingIds
    }

    /// Updates the notification permission denied state.
    public func updateNotificationPermissionDenied(_ denied: Bool) {
        self.notificationPermissionDenied = denied
    }

    /// Updates the setup required state.
    public func updateSetupRequired(_ required: Bool) {
        self.setupRequired = required
    }

    /// Builds the menu from current state.
    public func buildMenu() -> NSMenu {
        let menuItems = MenuBuilder.buildMenuItems(
            events: self.events,
            conflictingEventIds: self.conflictingEventIds,
            notificationPermissionDenied: self.notificationPermissionDenied,
            setupRequired: self.setupRequired
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
        case .setupRequired:
            self.createSetupRequiredItem()

        case .notificationWarning:
            self.createNotificationWarningItem()

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
}

// MARK: - Menu Item Creation

extension MenuController {
    private func createSetupRequiredItem() -> NSMenuItem {
        let title = "Setup Required"
        let subtitle = "Click to configure Google Calendar"

        let item = NSMenuItem(
            title: title,
            action: #selector(handleSettings(_:)),
            keyEquivalent: ""
        )
        item.target = self

        // Create attributed title with key icon and subtitle
        let keyIcon = NSAttributedString(
            string: "🔑 ",
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )
        let titleAttr = NSAttributedString(
            string: title + "\n",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        let subtitleAttr = NSAttributedString(
            string: subtitle,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )

        let fullTitle = NSMutableAttributedString()
        fullTitle.append(keyIcon)
        fullTitle.append(titleAttr)
        fullTitle.append(subtitleAttr)
        item.attributedTitle = fullTitle

        return item
    }

    private func createNotificationWarningItem() -> NSMenuItem {
        let title = "Notifications disabled"
        let subtitle = "Alerts won't appear. Click to enable."

        let item = NSMenuItem(
            title: title,
            action: #selector(handleOpenNotificationSettings(_:)),
            keyEquivalent: ""
        )
        item.target = self

        // Create attributed title with warning icon and subtitle
        let warningIcon = NSAttributedString(
            string: "⚠️ ",
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )
        let titleAttr = NSAttributedString(
            string: title + "\n",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.systemOrange,
            ]
        )
        let subtitleAttr = NSAttributedString(
            string: subtitle,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )

        let fullTitle = NSMutableAttributedString()
        fullTitle.append(warningIcon)
        fullTitle.append(titleAttr)
        fullTitle.append(subtitleAttr)
        item.attributedTitle = fullTitle

        return item
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
        case .openNotificationSettings:
            #selector(Self.handleOpenNotificationSettings(_:))
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
}

// MARK: - MenuController Action Handlers

extension MenuController {
    @objc func handleJoinMeeting(_ sender: NSMenuItem) {
        guard let event = sender.representedObject as? CalendarEvent else { return }

        if let callback = onJoinMeeting {
            callback(event)
        } else if let url = event.primaryMeetingURL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func handleEventClicked(_ sender: NSMenuItem) {
        guard let event = sender.representedObject as? CalendarEvent else { return }

        if let callback = onJoinMeeting {
            callback(event)
        } else if let url = event.primaryMeetingURL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func handleCopyLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }

        if let callback = onCopyLink {
            callback(url)
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
    }

    @objc func handleOpenInCalendar(_ sender: NSMenuItem) {
        guard let event = sender.representedObject as? CalendarEvent else { return }

        if let callback = onOpenInCalendar {
            callback(event)
        } else if let url = event.htmlLink {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func handleRefresh(_: NSMenuItem) {
        let optionHeld = NSEvent.modifierFlags.contains(.option)
        if optionHeld {
            UserDefaults.standard.set("debug", forKey: "logLevel")
        }
        self.onRefresh?()
    }

    @objc func handleSettings(_: NSMenuItem) {
        if let callback = onSettings {
            callback()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    @objc func handleQuit(_: NSMenuItem) {
        if let callback = onQuit {
            callback()
        } else {
            NSApp.terminate(nil)
        }
    }

    @objc func handleOpenNotificationSettings(_: NSMenuItem) {
        self.onOpenNotificationSettings?()
    }
}
