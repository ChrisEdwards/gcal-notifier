import Foundation

/// Determines display order when multiple meetings have overlapping alert times.
///
/// The prioritization order is:
/// 1. **User is organizer** - You scheduled it, you should be there
/// 2. **More attendees** - Larger meetings are harder to reschedule
/// 3. **Accepted status** - Accepted > Tentative > No response > Declined
/// 4. **Earlier start time** - Tie-breaker
public struct EventPrioritizer: Sendable {
    public init() {}

    /// Sorts events by priority, highest priority first.
    ///
    /// - Parameter events: The events to prioritize.
    /// - Returns: Events sorted by priority (highest first).
    public func prioritize(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.sorted { lhs, rhs in
            self.compare(lhs, rhs) == .orderedDescending
        }
    }

    /// Compares two events for priority ordering.
    ///
    /// - Returns: `.orderedDescending` if `lhs` has higher priority,
    ///            `.orderedAscending` if `rhs` has higher priority,
    ///            `.orderedSame` if they have equal priority.
    public func compare(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> ComparisonResult {
        // 1. Organizer first
        if lhs.isOrganizer != rhs.isOrganizer {
            return lhs.isOrganizer ? .orderedDescending : .orderedAscending
        }

        // 2. More attendees
        if lhs.attendeeCount != rhs.attendeeCount {
            return lhs.attendeeCount > rhs.attendeeCount ? .orderedDescending : .orderedAscending
        }

        // 3. Accepted status (higher priority value wins)
        if lhs.responseStatus.priority != rhs.responseStatus.priority {
            return lhs.responseStatus.priority > rhs.responseStatus.priority
                ? .orderedDescending
                : .orderedAscending
        }

        // 4. Earlier start time (earlier = higher priority)
        if lhs.startTime != rhs.startTime {
            return lhs.startTime < rhs.startTime ? .orderedDescending : .orderedAscending
        }

        return .orderedSame
    }
}
