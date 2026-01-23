import Foundation
import Testing

@testable import GCalNotifierCore

// MARK: - Test Helpers

/// Creates a test CalendarEvent with default values that can be overridden.
private func makeEvent(
    id: String = "test-event",
    calendarId: String = "primary",
    title: String = "Test Meeting",
    startTime: Date = Date(timeIntervalSince1970: 1_700_000_000),
    endTime: Date = Date(timeIntervalSince1970: 1_700_003_600),
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

// MARK: - EventPrioritizer Tests

@Suite("EventPrioritizer Tests")
struct EventPrioritizerTests {
    let prioritizer = EventPrioritizer()
    let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Organizer events are prioritized first")
    func prioritize_organizerFirst() {
        let organizerEvent = makeEvent(id: "organizer", isOrganizer: true, attendeeCount: 2)
        let attendeeEvent = makeEvent(id: "attendee", isOrganizer: false, attendeeCount: 10)

        let result = self.prioritizer.prioritize([attendeeEvent, organizerEvent])

        #expect(result[0].id == "organizer")
        #expect(result[1].id == "attendee")
    }

    @Test("Events with more attendees are prioritized when organizer status is equal")
    func prioritize_moreAttendeesFirst() {
        let largeEvent = makeEvent(id: "large", attendeeCount: 10)
        let smallEvent = makeEvent(id: "small", attendeeCount: 2)

        let result = self.prioritizer.prioritize([smallEvent, largeEvent])

        #expect(result[0].id == "large")
        #expect(result[1].id == "small")
    }

    @Test("Accepted events are prioritized over tentative")
    func prioritize_acceptedOverTentative() {
        let acceptedEvent = makeEvent(id: "accepted", responseStatus: .accepted)
        let tentativeEvent = makeEvent(id: "tentative", responseStatus: .tentative)

        let result = self.prioritizer.prioritize([tentativeEvent, acceptedEvent])

        #expect(result[0].id == "accepted")
        #expect(result[1].id == "tentative")
    }

    @Test("Tentative events are prioritized over needsAction")
    func prioritize_tentativeOverNeedsAction() {
        let tentativeEvent = makeEvent(id: "tentative", responseStatus: .tentative)
        let needsActionEvent = makeEvent(id: "needsAction", responseStatus: .needsAction)

        let result = self.prioritizer.prioritize([needsActionEvent, tentativeEvent])

        #expect(result[0].id == "tentative")
        #expect(result[1].id == "needsAction")
    }

    @Test("NeedsAction events are prioritized over declined")
    func prioritize_needsActionOverDeclined() {
        let needsActionEvent = makeEvent(id: "needsAction", responseStatus: .needsAction)
        let declinedEvent = makeEvent(id: "declined", responseStatus: .declined)

        let result = self.prioritizer.prioritize([declinedEvent, needsActionEvent])

        #expect(result[0].id == "needsAction")
        #expect(result[1].id == "declined")
    }

    @Test("Earlier start time is prioritized as tie-breaker")
    func prioritize_earlierStartTime() {
        let earlierEvent = makeEvent(
            id: "earlier",
            startTime: baseTime
        )
        let laterEvent = makeEvent(
            id: "later",
            startTime: baseTime.addingTimeInterval(600)
        )

        let result = self.prioritizer.prioritize([laterEvent, earlierEvent])

        #expect(result[0].id == "earlier")
        #expect(result[1].id == "later")
    }

    @Test("Multiple factors apply in correct order")
    func prioritize_multipleFactors() {
        // Event A: Organizer, 5 attendees, accepted, later time
        let eventA = makeEvent(
            id: "A",
            startTime: baseTime.addingTimeInterval(600),
            isOrganizer: true,
            attendeeCount: 5,
            responseStatus: .accepted
        )

        // Event B: Not organizer, 10 attendees, accepted, earlier time
        let eventB = makeEvent(
            id: "B",
            startTime: baseTime,
            isOrganizer: false,
            attendeeCount: 10,
            responseStatus: .accepted
        )

        // Event C: Not organizer, 5 attendees, tentative, earlier time
        let eventC = makeEvent(
            id: "C",
            startTime: baseTime,
            isOrganizer: false,
            attendeeCount: 5,
            responseStatus: .tentative
        )

        let result = self.prioritizer.prioritize([eventB, eventC, eventA])

        // A wins: organizer trumps all
        // B beats C: same organizer status, same attendees but B is accepted vs C tentative
        #expect(result[0].id == "A")
        #expect(result[1].id == "B")
        #expect(result[2].id == "C")
    }

    @Test("Empty array returns empty array")
    func prioritize_emptyArray() {
        let result = self.prioritizer.prioritize([])
        #expect(result.isEmpty)
    }

    @Test("Single event returns that event")
    func prioritize_singleEvent() {
        let event = makeEvent(id: "only")
        let result = self.prioritizer.prioritize([event])

        #expect(result.count == 1)
        #expect(result[0].id == "only")
    }

    @Test("Equal priority events maintain stable order")
    func prioritize_stableOrder() {
        // All events have identical priority factors
        let event1 = makeEvent(id: "1", startTime: baseTime, attendeeCount: 5)
        let event2 = makeEvent(id: "2", startTime: baseTime, attendeeCount: 5)
        let event3 = makeEvent(id: "3", startTime: baseTime, attendeeCount: 5)

        // The sorted result should be stable (maintain relative input order for equal elements)
        let result = self.prioritizer.prioritize([event1, event2, event3])

        #expect(result.count == 3)
        // Swift's sort is stable, so order should be preserved
        #expect(result[0].id == "1")
        #expect(result[1].id == "2")
        #expect(result[2].id == "3")
    }
}

// MARK: - Compare Function Tests

@Suite("EventPrioritizer Compare Tests")
struct EventPrioritizerCompareTests {
    let prioritizer = EventPrioritizer()
    let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Compare returns orderedDescending when first is organizer")
    func compare_organizerFirst() {
        let organizer = makeEvent(id: "org", isOrganizer: true)
        let attendee = makeEvent(id: "att", isOrganizer: false)

        #expect(self.prioritizer.compare(organizer, attendee) == .orderedDescending)
        #expect(self.prioritizer.compare(attendee, organizer) == .orderedAscending)
    }

    @Test("Compare returns orderedDescending when first has more attendees")
    func compare_moreAttendees() {
        let large = makeEvent(id: "large", attendeeCount: 10)
        let small = makeEvent(id: "small", attendeeCount: 2)

        #expect(self.prioritizer.compare(large, small) == .orderedDescending)
        #expect(self.prioritizer.compare(small, large) == .orderedAscending)
    }

    @Test("Compare returns orderedDescending when first has higher response priority")
    func compare_higherResponsePriority() {
        let accepted = makeEvent(id: "acc", responseStatus: .accepted)
        let tentative = makeEvent(id: "tent", responseStatus: .tentative)

        #expect(self.prioritizer.compare(accepted, tentative) == .orderedDescending)
        #expect(self.prioritizer.compare(tentative, accepted) == .orderedAscending)
    }

    @Test("Compare returns orderedDescending when first starts earlier")
    func compare_earlierStartTime() {
        let earlier = makeEvent(id: "early", startTime: baseTime)
        let later = makeEvent(id: "late", startTime: baseTime.addingTimeInterval(600))

        #expect(self.prioritizer.compare(earlier, later) == .orderedDescending)
        #expect(self.prioritizer.compare(later, earlier) == .orderedAscending)
    }

    @Test("Compare returns orderedSame for identical priority events")
    func compare_identicalPriority() {
        let event1 = makeEvent(
            id: "1",
            startTime: baseTime,
            isOrganizer: false,
            attendeeCount: 5,
            responseStatus: .accepted
        )
        let event2 = makeEvent(
            id: "2",
            startTime: baseTime,
            isOrganizer: false,
            attendeeCount: 5,
            responseStatus: .accepted
        )

        #expect(self.prioritizer.compare(event1, event2) == .orderedSame)
    }
}
