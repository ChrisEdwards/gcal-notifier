Here are my best revisions to the **gcal-notifier** design plan.

These changes focus on three areas: **architectural decoupling** (moving from imperative coordination to reactive streams), **data integrity** (removing fragile UserDefaults patterns), and **user experience refinement** (making the "Back-to-Back" logic safer).

---

### 1. Architecture: Reactive Data Flow via `EventRepository`

**Rationale:**
The original plan has the `SyncEngine` explicitly calling `EventCache.save()` and `AlertEngine.scheduleAlerts()`. This "push" model creates tight coupling. If you add a new feature (e.g., a "Next Meeting" widget), you have to modify the `SyncEngine` to update that widget too.

**Proposed Change:**
Introduce a central `EventRepository` that exposes an `AsyncStream<[CalendarEvent]>`. The `SyncEngine` feeds this stream, and `AlertEngine`, `StatusItemController`, and UI views subscribe to it. This ensures a Single Source of Truth (SSOT) and makes the system reactive. When the cache changes, the UI and Alerts update automatically without manual coordination.

**Git Diff:**

```diff
  ├── Sources/
  │   └── GCalNotifier/
...
  │       ├── Calendar/
  │           ├── GoogleCalendarClient.swift
  │           ├── SyncEngine.swift
- │           ├── EventCache.swift
+ │           ├── EventRepository.swift      # Central SSOT + AsyncStream publisher
  │           └── EventModels.swift
  │       ├── Alerts/
  │           ├── AlertEngine.swift
...

- actor EventCache {
-     private let fileURL: URL
-     func save(_ events: [CalendarEvent]) async throws
-     func load() async throws -> [CalendarEvent]
-     func clear() async throws
- }
+ actor EventRepository {
+     private var events: [CalendarEvent] = []
+     private let continuation: AsyncStream<[CalendarEvent]>.Continuation
+     let eventStream: AsyncStream<[CalendarEvent]>
+
+     init() {
+         var continuation: AsyncStream<[CalendarEvent]>.Continuation!
+         self.eventStream = AsyncStream { continuation = $0 }
+         self.continuation = continuation
+     }
+
+     func update(_ newEvents: [CalendarEvent]) async throws {
+         self.events = newEvents
+         try await persistToDisk(newEvents)
+         continuation.yield(newEvents) // Notify all subscribers
+     }
+ }

  // Startup Flow
- 6. Start `SyncEngine`, perform incremental sync
- 7. `AlertEngine` reconciles cached alerts with fresh data
+ 6. `AlertEngine` begins awaiting `EventRepository.eventStream`
+ 7. `StatusItemController` begins awaiting `EventRepository.eventStream`
+ 8. `SyncEngine` starts and feeds `EventRepository.update()`

```

---

### 2. Persistence: Replacing `@AppStorage` with `PreferencesManager`

**Rationale:**
The plan uses `@AppStorage` for complex types (arrays of calendars/keywords) by serializing them to JSON strings.

1. **Fragility:** If JSON encoding fails, the app crashes or loses settings.
2. **Performance:** Every read/write requires JSON serialization/deserialization on the main thread (since `@AppStorage` is property wrapper based).
3. **Limits:** `UserDefaults` is not designed for large lists of blocked keywords or calendar IDs.

**Proposed Change:**
Move configuration to a strongly-typed, disk-backed `PreferencesManager` actor using `Codable`. Keep `@AppStorage` only for simple UI flags (like `launchAtLogin`).

**Git Diff:**

```diff
- @Observable
- final class SettingsStore {
-     // Filtering (arrays stored as JSON strings)
-     @AppStorage("enabledCalendarsJSON") private var enabledCalendarsJSON: String = "[]"
-     @AppStorage("blockedKeywordsJSON") private var blockedKeywordsJSON: String = "[]"
-
-     var enabledCalendars: [String] {
-         get { decodeJSON(enabledCalendarsJSON) }
-         set { enabledCalendarsJSON = encodeJSON(newValue) }
-     }
- }

+ struct AppConfiguration: Codable, Sendable {
+     var enabledCalendars: Set<String> = []
+     var blockedKeywords: [String] = []
+     var forceAlertKeywords: [String] = ["Interview", "IMPORTANT"]
+     var alertStages: [AlertStage] = [.defaultStage1, .defaultStage2]
+ }
+
+ actor PreferencesManager {
+     private var config: AppConfiguration
+     private let fileURL: URL
+
+     func update(_ mutation: (inout AppConfiguration) -> Void) async throws {
+         mutation(&config)
+         try await save()
+     }
+ }

```

---

### 3. Logic: Safer "Back-to-Back" Meeting Handling

**Rationale:**
The current plan suppresses the "10-minute warning" if you are currently in a meeting.
*Risk:* If the current meeting runs over (very common), and the user is deeply focused, suppressing the modal means they might miss the *next* meeting entirely until the "2-minute" panic alarm.
*Improvement:* Instead of suppressing the alert, **downgrade the intrusion level**.

**Proposed Change:**
If "In Meeting" is detected, the "10-minute warning" should not be a modal, but a "Transient Notification" (macOS native notification or a custom non-modal banner) that slides in and plays a sound, but doesn't steal focus.

**Git Diff:**

```diff
  ### Back-to-Back Meeting Handling

  When meetings are back-to-back (next meeting starts within 5 minutes of previous ending):

- 1. **First alert suppression:** Skip the 10-minute warning if user is currently in another meeting
+ 1. **Intrusion Downgrade:** If user is in a meeting, the 10-minute warning changes from "Modal Window" to "Passive Banner".
+    - Plays a subtle "pock" sound (different from the alarm).
+    - Shows a transient notification: "Up Next: [Meeting Name] in 10m".
+    - Does not steal keyboard focus.
  2. **Transition alert:** Show "Next meeting starting" at end of current meeting

```

---

### 4. Robustness: Strategy Pattern for Link Extraction

**Rationale:**
The plan relies on a hardcoded list of regex patterns in `MeetingLinkExtraction`. As video providers change their URL structures or new ones appear (e.g., a company switches to "Huddles.app"), you have to modify the core parsing logic.

**Proposed Change:**
Implement a Strategy Pattern using a `MeetingProvider` enum. This makes the code testable (you can write unit tests for specifically extracting Zoom links vs. Teams links) and extensible.

**Git Diff:**

```diff
- // In MeetingLink Extraction
- 1. conferenceData.entryPoints[].uri
- 2. regex scan for zoom.us, teams.microsoft.com, etc...

+ enum MeetingPlatform: String, CaseIterable {
+     case googleMeet, zoom, teams, webex, slack, unknown
+
+     var domains: [String] { ... }
+     func extract(from text: String) -> URL? { ... }
+ }
+
+ struct MeetingLinkExtractor {
+     static func extract(from event: GCalEvent) -> MeetingLink? {
+         // 1. Priority: Structured Conference Data
+         if let entryPoint = event.conferenceData?.entryPoints.first(where: { $0.entryPointType == "video" }) {
+             return MeetingLink(url: entryPoint.uri, platform: .googleMeet)
+         }
+
+         // 2. Fallback: Strategy-based scanning
+         // Scans description/location using registered platforms
+         for platform in MeetingPlatform.allCases {
+             if let url = platform.extract(from: event.description ?? "") {
+                 return MeetingLink(url: url, platform: platform)
+             }
+         }
+         return nil
+     }
+ }

```

---

### 5. UX Feature: "Quick Actions" in Menu

**Rationale:**
The menu simply lists meetings. Users often need to do more than just "Join".

1. **Copy Link:** User needs to paste the Zoom link to a colleague in Slack who "didn't get the invite."
2. **Email/Chat:** Running late? Need to notify attendees quickly.

**Proposed Change:**
Add a secondary action menu (or right-click context menu in the SwiftUI list) for "Copy Link".

**Git Diff:**

```diff
  ### Menu Content
  ...
  │  Today's Meetings                   │
  │    ✓ Weekly Standup           10:00 │
+ │      [Right-click context menu:     │
+ │       - Copy Video Link             │
+ │       - Copy Meeting ID             │
+ │       - Open in Calendar (Web)]     │
  │    ✓ 1:1 with Sarah           14:00 │
  ...

```

---

### 6. Resilience: "Ghost" Deletion Handling

**Rationale:**
The plan relies on Sync Tokens. If an event is deleted in Google Calendar, the incremental sync returns a "deleted" status. The plan says "Explicitly detects deleted events." However, if the `AlertEngine` has *already* scheduled a `Task` or `Timer` for that event, simply updating the data model isn't enough. The scheduled task must be cancelled.

**Proposed Change:**
The `AlertEngine` must maintain a map of `[EventID: Task]` and actively cancel tasks when the `EventRepository` emits an update where that Event ID is missing or marked cancelled.

**Git Diff:**

```diff
  actor AlertEngine {
      // State
-     var scheduledAlerts: [ScheduledAlert]
+     private var scheduledTasks: [String: Task<Void, Never>] = [:] // Map EventID to running Timer Task

+     func reconcile(newEvents: [CalendarEvent]) {
+         let newEventIds = Set(newEvents.map { $0.id })
+
+         // 1. Cancel alerts for events that no longer exist or were declined
+         for (id, task) in scheduledTasks {
+             if !newEventIds.contains(id) {
+                 task.cancel()
+                 scheduledTasks.removeValue(forKey: id)
+                 Logger.info("Cancelled alert for removed event: \(id)")
+             }
+         }
+
+         // 2. Schedule new/modified events...
+     }
  }

```

---

### 7. Security: Bundle-ID check for Keychain

**Rationale:**
The plan mentions "Client secret and tokens stored in Keychain." For local development, macOS Keychain access groups can be tricky. If you change the bundle ID or team ID, you lose access to the tokens.

**Proposed Change:**
Explicitly define the Keychain Access Group in the entitlements and the code to ensure persistence across build updates (e.g., debug vs release builds).

**Git Diff:**

```diff
  ### Security Configuration
  - **App Sandbox:** Enabled with network + keychain entitlements
- - **Credentials:** Client secret and tokens stored in Keychain only (never on disk)
+ - **Credentials:** Stored in Keychain with explicit `kSecAttrService` set to `com.yourname.gcal-notifier.auth`.
+ - **Entitlements:** Add `keychain-access-groups` to ensure consistent access across version updates.

```

---

### Summary of Revisions

1. **Reactive Architecture:** Use `AsyncStream` and `EventRepository` to decouple sync from UI/Alerts.
2. **Better Persistence:** Use `Codable` structs + JSON files instead of `@AppStorage` for arrays.
3. **Intelligent Intrusion:** Downgrade alerts to "Passive" when in a meeting, rather than suppressing them.
4. **Strategy Pattern:** Isolate regex logic for video links into a testable Enum/Strategy.
5. **Task Management:** Explicitly map Event IDs to async Tasks to handle cancellations correctly.
6. **Context Menus:** Add "Copy Link" utility to the menu bar list.