import Foundation
import Testing
@testable import GCalNotifierCore

// MARK: - Test Helpers

/// Creates a temporary file URL for test isolation.
private func makeTempFileURL() -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let testDir = tempDir.appendingPathComponent(
        "ScheduledAlertsStoreTests-\(UUID().uuidString)",
        isDirectory: true
    )
    try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    return testDir.appendingPathComponent("alerts.json")
}

/// Cleans up a temporary test directory.
private func cleanupTempDir(_ url: URL) {
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.removeItem(at: dir)
}

/// Creates a test alert with specified parameters.
private func makeTestAlert(
    id: String = UUID().uuidString,
    eventId: String = "event-123",
    stage: AlertStage = .stage1,
    scheduledFireTime: Date = Date(),
    snoozeCount: Int = 0,
    originalFireTime: Date? = nil,
    eventTitle: String = "Test Meeting",
    eventStartTime: Date = Date().addingTimeInterval(600),
    eventEndTime: Date? = nil,
    joinURL: URL? = nil,
    calendarURL: URL? = nil,
    notificationPayload: AlertNotificationPayload? = nil
) -> ScheduledAlert {
    ScheduledAlert(
        id: id,
        eventId: eventId,
        stage: stage,
        scheduledFireTime: scheduledFireTime,
        snoozeCount: snoozeCount,
        originalFireTime: originalFireTime,
        eventTitle: eventTitle,
        eventStartTime: eventStartTime,
        eventEndTime: eventEndTime,
        joinURL: joinURL,
        calendarURL: calendarURL,
        notificationPayload: notificationPayload
    )
}

private func makeFullPersistenceAlert() throws -> ScheduledAlert {
    let startTime = Date(timeIntervalSince1970: 1_700_000_600)
    let joinURL = try #require(URL(string: "https://meet.google.com/full-alert"))
    let calendarURL = try #require(URL(string: "https://calendar.google.com/event?eid=full-alert"))
    let notificationPayload = AlertNotificationPayload(
        title: "Meeting starts soon",
        body: "Important Meeting starts at 10:10 AM",
        categoryIdentifier: AlertNotificationPayload.stage2CategoryIdentifier,
        soundBehavior: .defaultSound,
        urgency: .timeSensitive
    )

    return ScheduledAlert(
        id: "full-alert",
        eventId: "event-xyz",
        stage: .stage2,
        scheduledFireTime: Date(timeIntervalSince1970: 1_700_000_000),
        snoozeCount: 3,
        originalFireTime: Date(timeIntervalSince1970: 1_699_999_500),
        eventTitle: "Important Meeting",
        eventStartTime: startTime,
        eventEndTime: Date(timeIntervalSince1970: 1_700_004_200),
        joinURL: joinURL,
        calendarURL: calendarURL,
        notificationPayload: notificationPayload
    )
}

// MARK: - Save and Load Tests

@Suite("ScheduledAlertsStore Save and Load Tests")
struct ScheduledAlertsStoreSaveAndLoadTests {
    @Test("Save and load round trips")
    func saveAndLoadRoundTrips() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let alert1 = makeTestAlert(id: "alert-1", eventId: "event-1", stage: .stage1)
        let alert2 = makeTestAlert(id: "alert-2", eventId: "event-2", stage: .stage2)

        try await store.save([alert1, alert2])
        let loaded = try await store.load()

        #expect(loaded.count == 2)
        #expect(loaded.contains { $0.id == "alert-1" })
        #expect(loaded.contains { $0.id == "alert-2" })
    }

    @Test("Load when empty returns empty array")
    func loadWhenEmptyReturnsEmptyArray() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let loaded = try await store.load()

        #expect(loaded.isEmpty)
    }

    @Test("Save overwrites previous")
    func saveOverwritesPrevious() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let alert1 = makeTestAlert(id: "alert-1", eventTitle: "First Meeting")
        let alert2 = makeTestAlert(id: "alert-2", eventTitle: "Second Meeting")

        try await store.save([alert1])
        try await store.save([alert2])

        let loaded = try await store.load()

        #expect(loaded.count == 1)
        #expect(loaded.first?.id == "alert-2")
        #expect(loaded.first?.eventTitle == "Second Meeting")
    }

    @Test("Alert with snooze info persists")
    func alertWithSnoozeInfoPersists() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let originalTime = Date(timeIntervalSince1970: 1_700_000_000)
        let snoozedTime = Date(timeIntervalSince1970: 1_700_000_180)

        let alert = makeTestAlert(
            id: "snoozed-alert",
            scheduledFireTime: snoozedTime,
            snoozeCount: 2,
            originalFireTime: originalTime
        )

        try await store.save([alert])
        let loaded = try await store.load()

        #expect(loaded.count == 1)
        let loadedAlert = try #require(loaded.first)
        #expect(loadedAlert.snoozeCount == 2)
        #expect(loadedAlert.originalFireTime == originalTime)
        #expect(loadedAlert.scheduledFireTime == snoozedTime)
        #expect(loadedAlert.wasSnoozed)
    }

    @Test("Stage 2 presentation snapshot persists")
    func stage2PresentationSnapshotPersists() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let store = ScheduledAlertsStore(fileURL: fileURL)
        let fireTime = Date(timeIntervalSince1970: 1_800_000_000)
        let startTime = fireTime.addingTimeInterval(120)
        let endTime = startTime.addingTimeInterval(1800)
        let joinURL = try #require(URL(string: "https://meet.google.com/abc-defg-hij"))
        let calendarURL = try #require(URL(string: "https://calendar.google.com/event?eid=abc"))
        let payload = AlertNotificationPayload.make(
            eventTitle: "Durable Snapshot Meeting",
            eventStartTime: startTime,
            stage: .stage2
        )

        let alert = makeTestAlert(
            id: "snapshot-alert",
            eventId: "calendar-1::event-1",
            stage: .stage2,
            scheduledFireTime: fireTime,
            eventTitle: "Durable Snapshot Meeting",
            eventStartTime: startTime,
            eventEndTime: endTime,
            joinURL: joinURL,
            calendarURL: calendarURL,
            notificationPayload: payload
        )

        try await store.save([alert])
        let loaded = try await store.load()
        let loadedAlert = try #require(loaded.first)

        #expect(loadedAlert.eventTitle == "Durable Snapshot Meeting")
        #expect(loadedAlert.eventStartTime == startTime)
        #expect(loadedAlert.eventEndTime == endTime)
        #expect(loadedAlert.stage == .stage2)
        #expect(loadedAlert.scheduledFireTime == fireTime)
        #expect(loadedAlert.joinURL == joinURL)
        #expect(loadedAlert.calendarURL == calendarURL)
        #expect(loadedAlert.notificationPayload == payload)
    }
}

// MARK: - Persistence Tests

@Suite("ScheduledAlertsStore Persistence Tests")
struct ScheduledAlertsStorePersistenceTests {
    @Test("Data survives reload with new store instance")
    func dataSurvivesReload() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let alert1 = makeTestAlert(
            id: "alert-1",
            eventId: "event-1",
            stage: .stage1,
            scheduledFireTime: baseTime,
            eventTitle: "Persistent Meeting"
        )
        let alert2 = makeTestAlert(
            id: "alert-2",
            eventId: "event-2",
            stage: .stage2,
            scheduledFireTime: baseTime.addingTimeInterval(300),
            eventTitle: "Another Meeting"
        )

        // First store instance
        do {
            let store = ScheduledAlertsStore(fileURL: fileURL)
            try await store.save([alert1, alert2])
        }

        // New store instance loading from same file
        do {
            let store = ScheduledAlertsStore(fileURL: fileURL)
            let loaded = try await store.load()

            #expect(loaded.count == 2)
            #expect(loaded.contains { $0.id == "alert-1" && $0.eventTitle == "Persistent Meeting" })
            #expect(loaded.contains { $0.id == "alert-2" && $0.eventTitle == "Another Meeting" })
        }
    }

    @Test("All fields are preserved across reload")
    func allFieldsPreserved() async throws {
        let fileURL = makeTempFileURL()
        defer { cleanupTempDir(fileURL) }

        let alert = try makeFullPersistenceAlert()

        // Save with first instance
        do {
            let store = ScheduledAlertsStore(fileURL: fileURL)
            try await store.save([alert])
        }

        // Load with new instance and verify all fields
        do {
            let store = ScheduledAlertsStore(fileURL: fileURL)
            let loaded = try await store.load()

            #expect(loaded.count == 1)
            let loadedAlert = try #require(loaded.first)
            #expect(loadedAlert == alert)
        }
    }
}

// MARK: - AlertStage Tests

@Suite("AlertStage Tests")
struct AlertStageTests {
    @Test("Stage1 has correct default minutes")
    func stage1DefaultMinutes() {
        #expect(AlertStage.stage1.defaultMinutesBefore == 10)
    }

    @Test("Stage2 has correct default minutes")
    func stage2DefaultMinutes() {
        #expect(AlertStage.stage2.defaultMinutesBefore == 2)
    }

    @Test("Stage display names are human readable")
    func stageDisplayNames() {
        #expect(AlertStage.stage1.displayName == "Early Warning")
        #expect(AlertStage.stage2.displayName == "Urgent Reminder")
    }

    @Test("AlertStage is codable")
    func alertStageCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for stage in AlertStage.allCases {
            let data = try encoder.encode(stage)
            let decoded = try decoder.decode(AlertStage.self, from: data)
            #expect(decoded == stage)
        }
    }
}

// MARK: - ScheduledAlert Model Tests

@Suite("ScheduledAlert Model Tests")
struct ScheduledAlertModelTests {
    @Test("Snooze creates new alert with incremented count")
    func snoozeIncrementsCount() {
        let originalTime = Date(timeIntervalSince1970: 1_700_000_000)
        let newFireTime = Date(timeIntervalSince1970: 1_700_000_180)

        let alert = makeTestAlert(
            scheduledFireTime: originalTime,
            snoozeCount: 0
        )

        let snoozedAlert = alert.snoozed(until: newFireTime)

        #expect(snoozedAlert.snoozeCount == 1)
        #expect(snoozedAlert.scheduledFireTime == newFireTime)
        #expect(snoozedAlert.originalFireTime == originalTime)
        #expect(snoozedAlert.wasSnoozed)
    }

    @Test("Snooze preserves original fire time on subsequent snoozes")
    func snoozePreservesOriginalTime() {
        let originalTime = Date(timeIntervalSince1970: 1_700_000_000)
        let firstSnoozeTime = Date(timeIntervalSince1970: 1_700_000_180)
        let secondSnoozeTime = Date(timeIntervalSince1970: 1_700_000_360)

        let alert = makeTestAlert(scheduledFireTime: originalTime)
        let firstSnooze = alert.snoozed(until: firstSnoozeTime)
        let secondSnooze = firstSnooze.snoozed(until: secondSnoozeTime)

        #expect(secondSnooze.snoozeCount == 2)
        #expect(secondSnooze.scheduledFireTime == secondSnoozeTime)
        #expect(secondSnooze.originalFireTime == originalTime)
    }

    @Test("WasSnoozed returns false for fresh alerts")
    func wasSnoozedFalseForFresh() {
        let alert = makeTestAlert(snoozeCount: 0)
        #expect(!alert.wasSnoozed)
    }

    @Test("Alert is identifiable by id")
    func alertIdentifiable() {
        let alert = makeTestAlert(id: "unique-id-123")
        #expect(alert.id == "unique-id-123")
    }

    @Test("Alerts with same data are equal")
    func alertEquality() {
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        let startTime = Date(timeIntervalSince1970: 1_700_000_600)

        let alert1 = ScheduledAlert(
            id: "alert-1",
            eventId: "event-1",
            stage: .stage1,
            scheduledFireTime: time,
            snoozeCount: 0,
            originalFireTime: nil,
            eventTitle: "Meeting",
            eventStartTime: startTime
        )

        let alert2 = ScheduledAlert(
            id: "alert-1",
            eventId: "event-1",
            stage: .stage1,
            scheduledFireTime: time,
            snoozeCount: 0,
            originalFireTime: nil,
            eventTitle: "Meeting",
            eventStartTime: startTime
        )

        #expect(alert1 == alert2)
    }
}
