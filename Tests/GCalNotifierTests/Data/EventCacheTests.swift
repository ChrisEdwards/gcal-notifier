import Foundation
import Testing

@testable import GCalNotifierCore

// MARK: - Test Helpers

/// Creates a temporary file URL for test isolation.
private func makeTempFileURL() -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let testDir = tempDir.appendingPathComponent("EventCacheTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    return testDir.appendingPathComponent("events.json")
}

/// Cleans up a temporary test directory.
private func cleanupTempDir(_ url: URL) {
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.removeItem(at: dir)
}

/// Creates a test event with specified parameters.
private func makeTestEvent(
    id: String = UUID().uuidString,
    calendarId: String = "primary",
    title: String = "Test Meeting",
    startTime: Date = Date(),
    endTime: Date = Date().addingTimeInterval(3600),
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

// MARK: - Save and Load Tests

@Suite("EventCache Save and Load Tests")
struct EventCacheSaveAndLoadTests {
    @Test("Save and load round trips")
    func saveAndLoadRoundTrips() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)
        let event1 = makeTestEvent(id: "event-1", title: "Meeting 1")
        let event2 = makeTestEvent(id: "event-2", title: "Meeting 2")

        try await cache.save([event1, event2])
        let loaded = try await cache.load()

        #expect(loaded.count == 2)
        #expect(loaded.contains { $0.id == "event-1" })
        #expect(loaded.contains { $0.id == "event-2" })
    }

    @Test("Load when empty returns empty array")
    func loadWhenEmptyReturnsEmptyArray() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)
        let loaded = try await cache.load()

        #expect(loaded.isEmpty)
    }

    @Test("Clear removes all events")
    func clearRemovesAllEvents() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)
        let event1 = makeTestEvent(id: "event-1")
        let event2 = makeTestEvent(id: "event-2")

        try await cache.save([event1, event2])
        try await cache.clear()
        let loaded = try await cache.load()

        #expect(loaded.isEmpty)
    }
}

// MARK: - Query Tests

@Suite("EventCache Query Tests")
struct EventCacheQueryTests {
    @Test("Events from-to filters correctly")
    func eventsFromToFiltersCorrectly() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        // Event 1: 10:00 - 11:00
        let event1 = makeTestEvent(
            id: "event-1",
            title: "Morning Meeting",
            startTime: baseTime,
            endTime: baseTime.addingTimeInterval(3600)
        )

        // Event 2: 14:00 - 15:00
        let event2 = makeTestEvent(
            id: "event-2",
            title: "Afternoon Meeting",
            startTime: baseTime.addingTimeInterval(14400),
            endTime: baseTime.addingTimeInterval(18000)
        )

        // Event 3: 20:00 - 21:00
        let event3 = makeTestEvent(
            id: "event-3",
            title: "Evening Meeting",
            startTime: baseTime.addingTimeInterval(36000),
            endTime: baseTime.addingTimeInterval(39600)
        )

        try await cache.save([event1, event2, event3])

        // Query for 13:00 - 16:00 (should only get event 2)
        let filtered = try await cache.events(
            from: baseTime.addingTimeInterval(10800),
            to: baseTime.addingTimeInterval(21600)
        )

        #expect(filtered.count == 1)
        #expect(filtered.first?.id == "event-2")
    }

    @Test("Events overlapping time range are included")
    func eventsOverlappingTimeRangeAreIncluded() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        // Event spanning 10:00 - 14:00
        let event = makeTestEvent(
            id: "event-1",
            startTime: baseTime,
            endTime: baseTime.addingTimeInterval(14400)
        )

        try await cache.save([event])

        // Query for 12:00 - 13:00 (event overlaps this range)
        let filtered = try await cache.events(
            from: baseTime.addingTimeInterval(7200),
            to: baseTime.addingTimeInterval(10800)
        )

        #expect(filtered.count == 1)
        #expect(filtered.first?.id == "event-1")
    }

    @Test("NextEvent returns earliest")
    func nextEventReturnsEarliest() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        let event1 = makeTestEvent(
            id: "event-later",
            startTime: baseTime.addingTimeInterval(7200),
            endTime: baseTime.addingTimeInterval(10800)
        )
        let event2 = makeTestEvent(
            id: "event-earlier",
            startTime: baseTime.addingTimeInterval(3600),
            endTime: baseTime.addingTimeInterval(7200)
        )
        let event3 = makeTestEvent(
            id: "event-latest",
            startTime: baseTime.addingTimeInterval(10800),
            endTime: baseTime.addingTimeInterval(14400)
        )

        try await cache.save([event1, event2, event3])

        let next = try await cache.nextEvent(after: baseTime)

        #expect(next?.id == "event-earlier")
    }

    @Test("NextEvent returns nil when no future events")
    func nextEventReturnsNilWhenNoFutureEvents() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        let event = makeTestEvent(
            id: "event-past",
            startTime: baseTime,
            endTime: baseTime.addingTimeInterval(3600)
        )

        try await cache.save([event])

        // Query for events after the event start time
        let next = try await cache.nextEvent(after: baseTime.addingTimeInterval(7200))

        #expect(next == nil)
    }

    @Test("Events for calendar filters by ID")
    func eventsForCalendarFiltersById() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)

        let event1 = makeTestEvent(id: "event-1", calendarId: "work@example.com")
        let event2 = makeTestEvent(id: "event-2", calendarId: "personal@example.com")
        let event3 = makeTestEvent(id: "event-3", calendarId: "work@example.com")

        try await cache.save([event1, event2, event3])

        let workEvents = try await cache.events(forCalendar: "work@example.com")

        #expect(workEvents.count == 2)
        #expect(workEvents.allSatisfy { $0.calendarId == "work@example.com" })
    }
}

// MARK: - Update Tests

@Suite("EventCache Update Tests")
struct EventCacheUpdateTests {
    @Test("Update modifies existing event")
    func updateModifiesExistingEvent() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)
        let originalEvent = makeTestEvent(id: "event-1", title: "Original Title")

        try await cache.save([originalEvent])

        let updatedEvent = makeTestEvent(id: "event-1", title: "Updated Title")
        try await cache.update(updatedEvent)

        let loaded = try await cache.load()

        #expect(loaded.count == 1)
        #expect(loaded.first?.title == "Updated Title")
    }

    @Test("Update adds event if not present")
    func updateAddsEventIfNotPresent() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)
        let existingEvent = makeTestEvent(id: "event-1", title: "Existing")
        try await cache.save([existingEvent])

        let newEvent = makeTestEvent(id: "event-2", title: "New Event")
        try await cache.update(newEvent)

        let loaded = try await cache.load()

        #expect(loaded.count == 2)
        #expect(loaded.contains { $0.id == "event-1" })
        #expect(loaded.contains { $0.id == "event-2" })
    }

    @Test("Update does not overwrite events from other calendars")
    func updateDoesNotOverwriteOtherCalendarEvents() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)
        let event1 = makeTestEvent(id: "event-1", calendarId: "cal-1", title: "Calendar 1")
        let event2 = makeTestEvent(id: "event-1", calendarId: "cal-2", title: "Calendar 2")
        try await cache.save([event1, event2])

        let updatedEvent2 = makeTestEvent(id: "event-1", calendarId: "cal-2", title: "Updated Calendar 2")
        try await cache.update(updatedEvent2)

        let loaded = try await cache.load()
        #expect(loaded.count == 2)
        #expect(loaded.contains { $0.calendarId == "cal-1" && $0.title == "Calendar 1" })
        #expect(loaded.contains { $0.calendarId == "cal-2" && $0.title == "Updated Calendar 2" })
    }

    @Test("Remove deletes event")
    func removeDeletesEvent() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)
        let event1 = makeTestEvent(id: "event-1", title: "Keep")
        let event2 = makeTestEvent(id: "event-2", title: "Remove")

        try await cache.save([event1, event2])
        try await cache.remove(eventId: "event-2", calendarId: "primary")

        let loaded = try await cache.load()

        #expect(loaded.count == 1)
        #expect(loaded.first?.id == "event-1")
    }

    @Test("Remove only deletes event for matching calendar")
    func removeOnlyDeletesMatchingCalendar() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)
        let event1 = makeTestEvent(id: "event-1", calendarId: "cal-1", title: "Keep")
        let event2 = makeTestEvent(id: "event-1", calendarId: "cal-2", title: "Remove")

        try await cache.save([event1, event2])
        try await cache.remove(eventId: "event-1", calendarId: "cal-2")

        let loaded = try await cache.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.calendarId == "cal-1")
    }

    @Test("Remove nonexistent event does not throw")
    func removeNonexistentEventDoesNotThrow() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)
        let event = makeTestEvent(id: "event-1")
        try await cache.save([event])

        try await cache.remove(eventId: "nonexistent", calendarId: "primary")

        let loaded = try await cache.load()
        #expect(loaded.count == 1)
    }
}

// MARK: - Persistence Tests

@Suite("EventCache Persistence Tests")
struct EventCachePersistenceTests {
    @Test("Data survives reload with new cache instance")
    func dataSurvivesReload() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let event1 = makeTestEvent(id: "event-1", title: "Persistent Meeting")
        let event2 = makeTestEvent(id: "event-2", title: "Another Meeting")

        // First cache instance
        do {
            let cache = EventCache(fileURL: fileURL)
            try await cache.save([event1, event2])
        }

        // New cache instance loading from same file
        do {
            let cache = EventCache(fileURL: fileURL)
            let loaded = try await cache.load()

            #expect(loaded.count == 2)
            #expect(loaded.contains { $0.id == "event-1" && $0.title == "Persistent Meeting" })
            #expect(loaded.contains { $0.id == "event-2" && $0.title == "Another Meeting" })
        }
    }

    @Test("Clear persists across instances")
    func clearPersistsAcrossInstances() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let event = makeTestEvent(id: "event-1")

        // First instance: save and clear
        do {
            let cache = EventCache(fileURL: fileURL)
            try await cache.save([event])
            try await cache.clear()
        }

        // Second instance: verify still empty
        do {
            let cache = EventCache(fileURL: fileURL)
            let loaded = try await cache.load()
            #expect(loaded.isEmpty)
        }
    }

    @Test("Updates persist across instances")
    func updatesPersistAcrossInstances() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let original = makeTestEvent(id: "event-1", title: "Original")
        let updated = makeTestEvent(id: "event-1", title: "Updated")

        // First instance: save original then update
        do {
            let cache = EventCache(fileURL: fileURL)
            try await cache.save([original])
            try await cache.update(updated)
        }

        // Second instance: verify update persisted
        do {
            let cache = EventCache(fileURL: fileURL)
            let loaded = try await cache.load()

            #expect(loaded.count == 1)
            #expect(loaded.first?.title == "Updated")
        }
    }
}

// MARK: - Concurrent Access Tests

@Suite("EventCache Concurrent Access Tests")
struct EventCacheConcurrentAccessTests {
    @Test("Concurrent access does not corrupt data")
    func concurrentAccessDoesNotCorrupt() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let cache = EventCache(fileURL: fileURL)

        // Seed with initial events
        let initialEvents = (0 ..< 10).map { i in
            makeTestEvent(id: "initial-\(i)", title: "Initial \(i)")
        }
        try await cache.save(initialEvents)

        // Run concurrent operations
        await withTaskGroup(of: Void.self) { group in
            // Multiple concurrent reads
            for _ in 0 ..< 5 {
                group.addTask {
                    _ = try? await cache.load()
                }
            }

            // Multiple concurrent updates
            for i in 0 ..< 5 {
                group.addTask {
                    let event = makeTestEvent(id: "concurrent-\(i)", title: "Concurrent \(i)")
                    try? await cache.update(event)
                }
            }

            // Concurrent queries
            for _ in 0 ..< 3 {
                group.addTask {
                    let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
                    _ = try? await cache.events(from: baseTime, to: baseTime.addingTimeInterval(86400))
                }
            }

            await group.waitForAll()
        }

        // Verify final state is coherent
        let finalEvents = try await cache.load()

        // Should have initial events plus concurrent updates
        #expect(finalEvents.count >= 10)
        #expect(finalEvents.count <= 15)

        // All events should be valid (no corruption)
        for event in finalEvents {
            #expect(!event.id.isEmpty)
            #expect(!event.title.isEmpty)
        }
    }
}
