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
        case setupRequired
        case notificationWarning
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
        case openNotificationSettings
    }

    // MARK: - Public API

    /// Builds menu items for setup required state (before OAuth configured).
    /// - Returns: Array of menu items for setup required state.
    public static func buildSetupRequiredMenuItems() -> [MenuItem] {
        [
            .setupRequired,
            .separator,
            .action(title: "Settings...", action: .settings),
            .separator,
            .action(title: "Quit gcal-notifier", action: .quit),
        ]
    }

    /// Builds menu items from events and state.
    /// - Parameters:
    ///   - events: Calendar events to display
    ///   - conflictingEventIds: IDs of events that have conflicts
    ///   - notificationPermissionDenied: Whether notification permission was denied
    ///   - setupRequired: Whether OAuth setup is required (not yet configured)
    ///   - now: Current date for filtering (defaults to now)
    /// - Returns: Array of menu items to display
    public static func buildMenuItems(
        events: [CalendarEvent],
        conflictingEventIds: Set<String>,
        notificationPermissionDenied: Bool = false,
        setupRequired: Bool = false,
        now: Date = Date()
    ) -> [MenuItem] {
        // If setup is required, show simplified menu
        if setupRequired {
            return self.buildSetupRequiredMenuItems()
        }

        var items: [MenuItem] = []

        // Notification permission warning at the top
        if notificationPermissionDenied {
            items.append(.notificationWarning)
            items.append(.separator)
        }

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
