import Foundation

/// Determines which calendar events trigger alerts based on user settings.
///
/// Events must pass ALL filter checks:
/// 1. Not an all-day event
/// 2. Has meeting link OR contains force-alert keyword
/// 3. Calendar is enabled (empty enabledCalendars = all calendars)
/// 4. Does not contain blocked keywords
///
/// Keyword matching is case-insensitive substring matching against title and location.
public struct EventFilter: Sendable {
    private let settings: SettingsStore

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Determines whether the event should trigger an alert.
    public func shouldAlert(for event: CalendarEvent) -> Bool {
        // 1. All-day events never alert
        guard !event.isAllDay else { return false }

        // 2. Must have meeting link OR force-alert keyword
        let hasMeetingLink = !event.meetingLinks.isEmpty
        let hasForceKeyword = self.containsForceAlertKeyword(event)
        guard hasMeetingLink || hasForceKeyword else { return false }

        // 3. Calendar must be enabled (empty = all enabled)
        guard self.isCalendarEnabled(event.calendarId) else { return false }

        // 4. No blocked keywords (blocked overrides force-alert)
        guard !self.containsBlockedKeyword(event) else { return false }

        return true
    }

    // MARK: - Private Helpers

    private func isCalendarEnabled(_ calendarId: String) -> Bool {
        let enabled = self.settings.enabledCalendars
        // Empty list means all calendars are enabled
        guard !enabled.isEmpty else { return true }
        return enabled.contains(calendarId)
    }

    private func containsForceAlertKeyword(_ event: CalendarEvent) -> Bool {
        let keywords = self.settings.forceAlertKeywords
        return self.containsAnyKeyword(event, keywords: keywords)
    }

    private func containsBlockedKeyword(_ event: CalendarEvent) -> Bool {
        let keywords = self.settings.blockedKeywords
        return self.containsAnyKeyword(event, keywords: keywords)
    }

    private func containsAnyKeyword(_ event: CalendarEvent, keywords: [String]) -> Bool {
        guard !keywords.isEmpty else { return false }

        let searchableText = self.buildSearchableText(from: event)
        return keywords.contains { searchableText.localizedCaseInsensitiveContains($0) }
    }

    private func buildSearchableText(from event: CalendarEvent) -> String {
        var text = event.title
        if let location = event.location {
            text += " " + location
        }
        return text
    }
}
