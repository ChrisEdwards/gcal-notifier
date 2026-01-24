import Foundation

// MARK: - ConflictPair

/// Represents a pair of conflicting events.
public struct ConflictPair: Sendable, Equatable {
    public let first: CalendarEvent
    public let second: CalendarEvent

    public init(first: CalendarEvent, second: CalendarEvent) {
        self.first = first
        self.second = second
    }
}

// MARK: - ConflictDetector

/// Detects and reports overlapping meetings.
///
/// Events overlap if: A starts before B ends AND A ends after B starts.
/// Back-to-back meetings are NOT considered conflicts.
public struct ConflictDetector: Sendable {
    public init() {}

    /// Checks if two events overlap.
    ///
    /// Events overlap if: A starts before B ends AND A ends after B starts.
    /// Back-to-back is NOT a conflict (when A.endTime == B.startTime).
    ///
    /// - Parameters:
    ///   - a: First event to check
    ///   - b: Second event to check
    /// - Returns: `true` if the events overlap, `false` otherwise
    public func overlaps(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        // Back-to-back is NOT a conflict: A ends exactly when B starts (or vice versa)
        if a.endTime == b.startTime || b.endTime == a.startTime {
            return false
        }
        // Standard overlap check: A starts before B ends AND A ends after B starts
        return a.startTime < b.endTime && a.endTime > b.startTime
    }

    /// Finds all pairs of conflicting events from a list.
    ///
    /// Only considers alertable events (events with meeting links that are not all-day).
    ///
    /// - Parameter events: The list of events to check for conflicts
    /// - Returns: Array of conflict pairs, each containing two overlapping events
    public func findConflicts(in events: [CalendarEvent]) -> [ConflictPair] {
        // Filter to only alertable events
        let alertableEvents = events.filter(\.shouldAlert)
        var conflicts: [ConflictPair] = []

        // Compare each pair of events
        for i in 0 ..< alertableEvents.count {
            for j in (i + 1) ..< alertableEvents.count {
                let eventA = alertableEvents[i]
                let eventB = alertableEvents[j]
                if self.overlaps(eventA, eventB) {
                    conflicts.append(ConflictPair(first: eventA, second: eventB))
                }
            }
        }

        return conflicts
    }

    /// Finds all events that conflict with a specific event.
    ///
    /// - Parameters:
    ///   - event: The event to check conflicts against
    ///   - events: The list of events to check
    /// - Returns: Array of events that overlap with the given event
    public func eventsConflictingWith(
        _ event: CalendarEvent,
        in events: [CalendarEvent]
    ) -> [CalendarEvent] {
        events.filter { other in
            // Don't compare event to itself
            guard other.qualifiedId != event.qualifiedId else { return false }
            return self.overlaps(event, other)
        }
    }
}
