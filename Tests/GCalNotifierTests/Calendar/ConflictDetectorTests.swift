import Foundation
import Testing
@testable import GCalNotifierCore

// MARK: - Test Helpers

/// Static test URLs for meeting links.
private enum TestURLs {
    static let googleMeet = URL(string: "https://meet.google.com/abc-defg-hij")
}

/// Creates a test CalendarEvent with default values that can be overridden.
private func makeEvent(
    id: String = "test-event-1",
    calendarId: String = "primary",
    title: String = "Test Meeting",
    startTime: Date,
    endTime: Date,
    isAllDay: Bool = false,
    location: String? = nil,
    meetingLinks: [MeetingLink] = [],
    isOrganizer: Bool = false,
    attendeeCount: Int = 2,
    responseStatus: ResponseStatus = .accepted
) -> CalendarEvent {
    CalendarEvent(
        id: id,
        calendarId: calendarId,
        title: title,
        startTime: startTime,
        endTime: endTime,
        isAllDay: isAllDay,
        location: location,
        meetingLinks: meetingLinks,
        isOrganizer: isOrganizer,
        attendeeCount: attendeeCount,
        responseStatus: responseStatus
    )
}

/// Creates an event with meeting link (alertable by default).
private func makeAlertableEvent(
    id: String = "test-event-1",
    title: String = "Test Meeting",
    startTime: Date,
    endTime: Date
) throws -> CalendarEvent {
    let meetingURL = try #require(TestURLs.googleMeet)
    return makeEvent(
        id: id,
        title: title,
        startTime: startTime,
        endTime: endTime,
        meetingLinks: [MeetingLink(url: meetingURL)]
    )
}

// MARK: - ConflictPair Tests

@Suite("ConflictPair Tests")
struct ConflictPairTests {
    @Test("ConflictPair equality checks both events")
    func conflictPairEquality() throws {
        let now = Date()
        let eventA = try makeAlertableEvent(id: "a", startTime: now, endTime: now.addingTimeInterval(3600))
        let eventB = try makeAlertableEvent(id: "b", startTime: now, endTime: now.addingTimeInterval(3600))

        let pair1 = ConflictPair(first: eventA, second: eventB)
        let pair2 = ConflictPair(first: eventA, second: eventB)

        #expect(pair1 == pair2)
    }
}

// MARK: - Overlaps Tests

@Suite("ConflictDetector Overlaps Tests")
struct ConflictDetectorOverlapsTests {
    private let detector = ConflictDetector()

    @Test("Same time events overlap")
    func overlaps_sameTime_returnsTrue() throws {
        let now = Date()
        let eventA = try makeAlertableEvent(
            id: "a",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )
        let eventB = try makeAlertableEvent(
            id: "b",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )

        #expect(self.detector.overlaps(eventA, eventB) == true)
    }

    @Test("Partial overlap detected")
    func overlaps_partialOverlap_returnsTrue() throws {
        let now = Date()
        // Event A: 10:00 - 11:00
        let eventA = try makeAlertableEvent(
            id: "a",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )
        // Event B: 10:30 - 11:30 (starts during A)
        let eventB = try makeAlertableEvent(
            id: "b",
            startTime: now.addingTimeInterval(1800),
            endTime: now.addingTimeInterval(5400)
        )

        #expect(self.detector.overlaps(eventA, eventB) == true)
    }

    @Test("Non-overlapping events do not conflict")
    func overlaps_noOverlap_returnsFalse() throws {
        let now = Date()
        // Event A: 10:00 - 11:00
        let eventA = try makeAlertableEvent(
            id: "a",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )
        // Event B: 12:00 - 13:00 (1 hour after A ends)
        let eventB = try makeAlertableEvent(
            id: "b",
            startTime: now.addingTimeInterval(7200),
            endTime: now.addingTimeInterval(10800)
        )

        #expect(self.detector.overlaps(eventA, eventB) == false)
    }

    @Test("Back-to-back events are NOT a conflict")
    func overlaps_backToBack_returnsFalse() throws {
        let now = Date()
        // Event A: 10:00 - 11:00
        let eventA = try makeAlertableEvent(
            id: "a",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )
        // Event B: 11:00 - 12:00 (starts exactly when A ends)
        let eventB = try makeAlertableEvent(
            id: "b",
            startTime: now.addingTimeInterval(3600),
            endTime: now.addingTimeInterval(7200)
        )

        #expect(self.detector.overlaps(eventA, eventB) == false)
    }

    @Test("Event contained within another is a conflict")
    func overlaps_containedEvent_returnsTrue() throws {
        let now = Date()
        // Event A: 10:00 - 12:00
        let eventA = try makeAlertableEvent(
            id: "a",
            startTime: now,
            endTime: now.addingTimeInterval(7200)
        )
        // Event B: 10:30 - 11:30 (entirely within A)
        let eventB = try makeAlertableEvent(
            id: "b",
            startTime: now.addingTimeInterval(1800),
            endTime: now.addingTimeInterval(5400)
        )

        #expect(self.detector.overlaps(eventA, eventB) == true)
    }

    @Test("Overlap detection is symmetric")
    func overlaps_isSymmetric() throws {
        let now = Date()
        let eventA = try makeAlertableEvent(
            id: "a",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )
        let eventB = try makeAlertableEvent(
            id: "b",
            startTime: now.addingTimeInterval(1800),
            endTime: now.addingTimeInterval(5400)
        )

        #expect(self.detector.overlaps(eventA, eventB) == self.detector.overlaps(eventB, eventA))
    }
}

// MARK: - FindConflicts Tests

@Suite("ConflictDetector FindConflicts Tests")
struct ConflictDetectorFindConflictsTests {
    private let detector = ConflictDetector()

    @Test("Two conflicting events returns one pair")
    func findConflicts_twoConflicting_returnsOnePair() throws {
        let now = Date()
        let eventA = try makeAlertableEvent(
            id: "a",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )
        let eventB = try makeAlertableEvent(
            id: "b",
            startTime: now.addingTimeInterval(1800),
            endTime: now.addingTimeInterval(5400)
        )

        let conflicts = self.detector.findConflicts(in: [eventA, eventB])

        #expect(conflicts.count == 1)
        #expect(conflicts.first?.first.id == "a")
        #expect(conflicts.first?.second.id == "b")
    }

    @Test("Non-alertable events are excluded from conflict detection")
    func findConflicts_onlyConsidersAlertableEvents() {
        let now = Date()
        // Event A: alertable (has meeting link)
        let eventA = makeEvent(
            id: "a",
            startTime: now,
            endTime: now.addingTimeInterval(3600),
            meetingLinks: []
        )
        // Event B: not alertable (no meeting link)
        let eventB = makeEvent(
            id: "b",
            startTime: now,
            endTime: now.addingTimeInterval(3600),
            meetingLinks: []
        )

        let conflicts = self.detector.findConflicts(in: [eventA, eventB])

        #expect(conflicts.isEmpty)
    }

    @Test("All-day events are excluded from conflict detection")
    func findConflicts_excludesAllDayEvents() throws {
        let now = Date()
        let meetingURL = try #require(TestURLs.googleMeet)
        // Event A: all-day event with meeting link
        let eventA = makeEvent(
            id: "a",
            startTime: now,
            endTime: now.addingTimeInterval(86400),
            isAllDay: true,
            meetingLinks: [MeetingLink(url: meetingURL)]
        )
        // Event B: regular event with meeting link
        let eventB = makeEvent(
            id: "b",
            startTime: now,
            endTime: now.addingTimeInterval(3600),
            meetingLinks: [MeetingLink(url: meetingURL)]
        )

        let conflicts = self.detector.findConflicts(in: [eventA, eventB])

        #expect(conflicts.isEmpty)
    }

    @Test("Three overlapping events returns three pairs")
    func findConflicts_threeOverlapping_returnsThreePairs() throws {
        let now = Date()
        let eventA = try makeAlertableEvent(
            id: "a",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )
        let eventB = try makeAlertableEvent(
            id: "b",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )
        let eventC = try makeAlertableEvent(
            id: "c",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )

        let conflicts = self.detector.findConflicts(in: [eventA, eventB, eventC])

        #expect(conflicts.count == 3)
    }

    @Test("Empty event list returns empty conflicts")
    func findConflicts_emptyList_returnsEmpty() {
        let conflicts = self.detector.findConflicts(in: [])

        #expect(conflicts.isEmpty)
    }

    @Test("Single event returns no conflicts")
    func findConflicts_singleEvent_returnsEmpty() throws {
        let now = Date()
        let event = try makeAlertableEvent(
            id: "a",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )

        let conflicts = self.detector.findConflicts(in: [event])

        #expect(conflicts.isEmpty)
    }

    @Test("Back-to-back events return no conflicts")
    func findConflicts_backToBack_returnsEmpty() throws {
        let now = Date()
        let eventA = try makeAlertableEvent(
            id: "a",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )
        let eventB = try makeAlertableEvent(
            id: "b",
            startTime: now.addingTimeInterval(3600),
            endTime: now.addingTimeInterval(7200)
        )

        let conflicts = self.detector.findConflicts(in: [eventA, eventB])

        #expect(conflicts.isEmpty)
    }
}

// MARK: - EventsConflictingWith Tests

@Suite("ConflictDetector EventsConflictingWith Tests")
struct ConflictingWithTests {
    private let detector = ConflictDetector()

    @Test("Finds all events conflicting with target")
    func eventsConflictingWith_findsAll() throws {
        let now = Date()
        let target = try makeAlertableEvent(
            id: "target",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )
        let conflicting = try makeAlertableEvent(
            id: "conflict",
            startTime: now.addingTimeInterval(1800),
            endTime: now.addingTimeInterval(5400)
        )
        let nonConflicting = try makeAlertableEvent(
            id: "noconflict",
            startTime: now.addingTimeInterval(7200),
            endTime: now.addingTimeInterval(10800)
        )

        let result = self.detector.eventsConflictingWith(target, in: [target, conflicting, nonConflicting])

        #expect(result.count == 1)
        #expect(result.first?.id == "conflict")
    }

    @Test("Does not include target event in results")
    func eventsConflictingWith_excludesTarget() throws {
        let now = Date()
        let target = try makeAlertableEvent(
            id: "target",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )

        let result = self.detector.eventsConflictingWith(target, in: [target])

        #expect(result.isEmpty)
    }

    @Test("Returns empty when no conflicts")
    func eventsConflictingWith_noConflicts_returnsEmpty() throws {
        let now = Date()
        let target = try makeAlertableEvent(
            id: "target",
            startTime: now,
            endTime: now.addingTimeInterval(3600)
        )
        let other = try makeAlertableEvent(
            id: "other",
            startTime: now.addingTimeInterval(7200),
            endTime: now.addingTimeInterval(10800)
        )

        let result = self.detector.eventsConflictingWith(target, in: [target, other])

        #expect(result.isEmpty)
    }
}
