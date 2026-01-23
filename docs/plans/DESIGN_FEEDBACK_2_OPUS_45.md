# Design Feedback: gcal-notifier

**Reviewer:** Claude Opus 4.5
**Date:** 2026-01-22
**Document Reviewed:** DESIGN.md (gcal-notifier)

---

## Executive Summary

This is a well-structured design document with clear problem definition, sensible technology choices, and thoughtful consideration of edge cases. The proposed changes below focus on:

1. **Reliability** - Using system-level scheduling, proper concurrency patterns, and graceful degradation
2. **Architecture** - Better separation of concerns, explicit state machines, and testability
3. **Features** - High-value additions that leverage existing infrastructure
4. **Security** - Defense in depth for credential storage

---

## 1. Critical Architecture Improvement: Event-Driven Alert Scheduling

### Issue
The current design uses wall-clock based scheduling with periodic reconciliation, but doesn't leverage macOS's built-in scheduling infrastructure.

### Analysis
Using `Timer` for alert scheduling is fragile across sleep/wake cycles and system time changes. macOS provides `UNUserNotificationCenter` with proper scheduling that survives sleep, handles time changes, and integrates with system notification management. Even though you're showing custom modals, you can use the notification trigger mechanism for timing.

### Rationale
- `Timer` fires drift after sleep (unless you reconcile, which adds complexity)
- System-level scheduling handles DST changes, time zone changes, NTP corrections
- Reduces wake-from-sleep reconciliation complexity
- Battery-efficient (doesn't need app polling to fire alerts)

### Diff

````diff
 ### AlertEngine Architecture

 A central state machine that owns all alert logic:

 ```swift
 actor AlertEngine {
     // Core responsibilities
     func scheduleAlerts(for events: [CalendarEvent])
     func cancelAlerts(for eventId: String)
     func snooze(eventId: String, duration: TimeInterval)
     func acknowledgeAlert(eventId: String)

     // Recovery
-    func reconcileOnWake()
-    func reconcileOnRelaunch()
+    func reconcileOnRelaunch()  // Only needed for app restart, not wake

     // State
     var scheduledAlerts: [ScheduledAlert]
     var acknowledgedEvents: Set<String>
+
+    // Implementation uses UNUserNotificationCenter for scheduling
+    // with custom notification category that triggers modal display
 }
 ```

 **Key properties:**
--Deterministic scheduling (wall-clock based, not timer drift)
+-Deterministic scheduling via UNCalendarNotificationTrigger
 - Persists scheduled alerts to disk
--Reconciles on wake/relaunch
+-Reconciles on relaunch only (system handles wake scenarios)
 - Guarantees "exactly once" alert delivery
 - Cancels/reschedules on event mutation
 - Tracks acknowledgment state per event
+
+**System notification integration:**
+- Register custom notification category with hidden presentation
+- Notification delivery triggers `userNotificationCenter(_:willPresent:)`
+- Delegate intercepts and shows custom modal instead of system notification
+- Provides reliable timing even during sleep
````

---

## 2. Reliability Improvement: Distributed Notifications for Multi-Instance Prevention

### Issue
No handling for multiple instances of the app running simultaneously.

### Analysis
If users accidentally launch the app twice (e.g., from different paths during development, or corrupted launch agent), you'll get duplicate alerts and race conditions on the event cache.

### Rationale
- Simple single-instance enforcement prevents user confusion
- Prevents duplicate modals and sounds
- Protects data integrity of cache files

### Diff

````diff
 ### App Configuration

 - `LSUIElement = true` in Info.plist (no Dock icon)
 - Menu bar only presence
 - Launch at login enabled by default via `SMAppService`
+- Single instance enforcement via `NSDistributedNotificationCenter`
+
+### Single Instance Enforcement
+
+```swift
+// In AppDelegate.applicationDidFinishLaunching
+let runningInstances = NSRunningApplication.runningApplications(
+    withBundleIdentifier: Bundle.main.bundleIdentifier!
+)
+if runningInstances.count > 1 {
+    // Another instance is already running
+    // Optionally: send notification to bring existing instance to front
+    NSDistributedNotificationCenter.default().postNotificationName(
+        Notification.Name("com.gcal-notifier.bringToFront"),
+        object: nil
+    )
+    NSApp.terminate(nil)
+}
+```
````

---

## 3. New Feature: Meeting Intelligence - Prep Time Detection

### Issue
Not all meetings are equal. Some require preparation that the current system doesn't account for.

### Analysis
Users often need different lead times for different meeting types. An interview requires 15 minutes of prep to review the candidate. A quick standup needs none. The current design treats all meetings identically.

### Rationale
- Significantly increases practical utility
- Leverages existing keyword infrastructure
- Low implementation cost, high user value

### Diff

````diff
 ### Filtering & Configuration

+### Prep Time Rules
+
+Allow users to define meeting categories with custom alert timing:
+
+```swift
+struct PrepTimeRule: Codable, Identifiable {
+    let id: UUID
+    var keyword: String           // Matched against title/description
+    var prepTimeMinutes: Int      // Additional time before stage 1 alert
+    var priority: Int             // Higher = matched first
+}
+```
+
+**Example rules:**
+| Keyword | Prep Time | Effect |
+|---------|-----------|--------|
+| "Interview" | 15 min | Stage 1 fires at 25 min (10 + 15) |
+| "Presentation" | 20 min | Stage 1 fires at 30 min (10 + 20) |
+| "1:1" | 5 min | Stage 1 fires at 15 min (10 + 5) |
+
+**Implementation:**
+- Check prep rules before scheduling alerts
+- Add prep time to each stage's offset
+- Show "(includes 15m prep)" in alert modal
+- Persisted in SettingsStore as JSON array
+
 ### Settings Storage

 ```swift
 @Observable
 final class SettingsStore {
     // ... existing properties ...

+    // Prep time rules
+    @AppStorage("prepTimeRulesJSON") private var prepTimeRulesJSON: String = "[]"
+
+    var prepTimeRules: [PrepTimeRule] {
+        get { decodeJSON(prepTimeRulesJSON) }
+        set { prepTimeRulesJSON = encodeJSON(newValue) }
+    }
````

---

## 4. Architecture Improvement: Proper Dependency Injection

### Issue
The design implies singletons/global access for core services, which complicates testing and creates hidden dependencies.

### Analysis
Components like `SyncEngine`, `AlertEngine`, and `SettingsStore` need clear ownership and dependency relationships. The current structure doesn't specify how these interact.

### Rationale
- Enables unit testing without mocking singletons
- Makes data flow explicit and debuggable
- Prevents retain cycles and memory issues

### Diff

````diff
+### Dependency Container
+
+```swift
+@MainActor
+final class AppContainer {
+    // Core services (order matters for initialization)
+    let settingsStore: SettingsStore
+    let keychainManager: KeychainManager
+    let eventCache: EventCache
+    let alertsStore: ScheduledAlertsStore
+
+    // Depends on core services
+    let oauthProvider: OAuthProvider
+    let calendarClient: GoogleCalendarClient
+    let syncEngine: SyncEngine
+    let alertEngine: AlertEngine
+    let soundPlayer: SoundPlayer
+
+    // UI controllers
+    let statusItemController: StatusItemController
+    let alertWindowController: AlertWindowController
+
+    init() {
+        // Initialize in dependency order
+        settingsStore = SettingsStore()
+        keychainManager = KeychainManager()
+        eventCache = EventCache()
+        alertsStore = ScheduledAlertsStore()
+
+        oauthProvider = GoogleOAuthProvider(
+            keychain: keychainManager,
+            settings: settingsStore
+        )
+        calendarClient = GoogleCalendarClient(oauth: oauthProvider)
+        // ... etc
+    }
+}
+```
+
+**Benefits:**
+- Clear initialization order
+- Easy to create test doubles
+- Single source of truth for service instances
+- Explicit lifecycle management
+
 ### Project Structure
````

---

## 5. Robustness Improvement: Graceful Degradation During Sync Failures

### Issue
The sync failure handling is binary—either it works or shows an error. No partial success handling beyond "show events that succeeded."

### Analysis
In practice, calendar sync can fail for individual calendars while others succeed. The design should maintain a per-calendar health status.

### Rationale
- Users shouldn't lose all alerts because one shared calendar is flaky
- Provides actionable diagnostics
- Improves perceived reliability

### Diff

````diff
 ### Calendar API Errors

 | Error | Handling |
 |-------|----------|
 | Rate limited (403) | Exponential backoff with jitter, show warning in menu |
 | Sync token invalid (410) | Clear sync token, perform full re-sync |
 | Calendar not found | Remove from enabled list, notify user |
-| Partial failure | Show events that succeeded, log failures |
+| Partial failure | Continue with healthy calendars, track per-calendar status |
+
+### Per-Calendar Health Tracking
+
+```swift
+struct CalendarHealth: Codable {
+    var calendarId: String
+    var lastSuccessfulSync: Date?
+    var consecutiveFailures: Int = 0
+    var lastError: String?
+    var status: HealthStatus
+
+    enum HealthStatus: String, Codable {
+        case healthy      // Last sync succeeded
+        case degraded     // 1-2 failures, still trying
+        case failing      // 3+ failures, reduced polling
+        case disabled     // User action required
+    }
+}
+```
+
+**Behavior by status:**
+| Status | Polling | UI Indicator | Recovery |
+|--------|---------|--------------|----------|
+| healthy | Normal | None | - |
+| degraded | Normal | None | Auto-retry |
+| failing | 4x slower | Yellow dot on calendar | Auto-retry with backoff |
+| disabled | None | Red dot, prompt | Manual re-enable |
+
+**Menu display with health:**
+```
+│  Today's Meetings                   │
+│    ✓ Weekly Standup           10:00 │
+│    ⚠ Team Calendar (sync issues)    │
+```
````

---

## 6. New Feature: Quick Reschedule from Alert Modal

### Issue
Snooze only delays the alert. Users often need to actually reschedule the meeting when they realize they can't attend.

### Analysis
When an alert fires and a user realizes they have a conflict, the current flow requires: dismiss alert → open calendar → find event → reschedule. This is friction during exactly the moment they're time-pressed.

### Rationale
- High-value addition to the core alert interaction
- Doesn't require write permissions (opens Google Calendar URL with prefilled data)
- Keeps app scope manageable (no Calendar write API needed)

### Diff

````diff
 **Button actions:**
 - **Join Meeting:** Opens meeting URL via `NSWorkspace.shared.open(url)`, closes window
 - **Snooze:** Dropdown with options (1 min, 3 min, 5 min). Reschedules alert.
 - **Dismiss:** Closes window, marks event acknowledged (no further alerts for this event)
+- **Reschedule:** Opens Google Calendar edit page for the event (read-only app, uses web)
+
+**Reschedule implementation:**
+- Construct URL: `https://calendar.google.com/calendar/r/eventedit/{eventId}`
+- Opens in default browser
+- User edits in Google Calendar
+- Next sync picks up the changes
+- No write API permissions required

 **Single meeting modal:**
 ```
 ┌─────────────────────────────────────┐
 │  Meeting in 10 minutes              │
 │                                     │
 │  Weekly Team Standup                │
 │  10:00 AM - 10:30 AM                │
 │                                     │
-│  [Join Meeting]  [Snooze ▾]  [Dismiss]│
+│  [Join Meeting]  [Snooze ▾]  [Reschedule]  [✕]│
 └─────────────────────────────────────┘
 ```
+
+Note: Dismiss becomes a simple close button (✕) to make room for Reschedule.
````

---

## 7. Performance Improvement: Lazy Calendar List Loading

### Issue
The design fetches all events from all enabled calendars on every sync, even if user hasn't opened the calendar list recently.

### Analysis
For users with many calendars (10+), fetching the calendar list metadata on every startup adds latency. The list rarely changes.

### Rationale
- Faster cold start
- Reduced API calls
- Better UX for users with many calendars

### Diff

````diff
 **Calendar list endpoint:**
 ```
 GET https://www.googleapis.com/calendar/v3/users/me/calendarList
 ```
+
+**Calendar list caching:**
+- Cache calendar list separately from events
+- Refresh calendar list:
+  - On first launch after auth
+  - When user opens Calendars preferences tab
+  - Every 24 hours in background
+  - On explicit refresh request
+- Events sync uses cached calendar IDs
+- New calendars discovered on list refresh automatically disabled (user must enable)
````

---

## 8. New Feature: Meeting Outcome Quick Actions

### Issue
After a meeting, there's no closure. The event just disappears from the list.

### Analysis
Users often need to take action after meetings: send follow-up, log notes, update a ticket. A brief post-meeting prompt leverages the context while it's fresh.

### Rationale
- Differentiating feature (no calendar app does this well)
- Capitalizes on existing alert infrastructure
- Optional feature that power users will love

### Diff

````diff
+### Post-Meeting Quick Actions
+
+When a meeting with video link ends (configurable):
+
+```
+┌─────────────────────────────────────┐
+│  Meeting Ended                      │
+│  Weekly Team Standup                │
+│                                     │
+│  [Add Follow-up ▾]  [Log Time]  [✕] │
+└─────────────────────────────────────┘
+```
+
+**Quick actions (configurable per user):**
+- **Add Follow-up:** Opens compose window for:
+  - Email to attendees (mailto: with prefilled recipients)
+  - Slack message (slack://channel if configured)
+  - Calendar event (create follow-up meeting)
+- **Log Time:** For freelancers/contractors
+  - Quick time entry (30m, 1h, custom)
+  - Copies meeting details to clipboard for timesheet
+- **Create Task:** Opens configured task manager
+  - Todoist, Things, OmniFocus URL schemes
+  - Prefills meeting title
+
+**Settings:**
+```swift
+@AppStorage("showPostMeetingPrompt") var showPostMeetingPrompt: Bool = false
+@AppStorage("postMeetingPromptDelay") var postMeetingPromptDelay: Int = 2 // minutes after end
+@AppStorage("enabledPostMeetingActions") var enabledPostMeetingActions: [String] = []
+```
+
+**Note:** This is a v1.5 feature - foundational infrastructure only in v1.
````

---

## 9. Robustness Improvement: Structured Concurrency with TaskGroups

### Issue
The design doesn't specify how concurrent calendar fetches are coordinated.

### Analysis
When syncing multiple calendars, using unstructured `Task {}` blocks makes cancellation and error propagation difficult. Swift's structured concurrency with `TaskGroup` provides proper lifecycle management.

### Rationale
- Automatic cancellation propagation
- Better error aggregation
- Cleaner resource cleanup
- Avoids task leaks

### Diff

````diff
 ### Sync Strategy

+**Multi-calendar sync implementation:**
+
+```swift
+func syncAllCalendars() async throws -> [CalendarEvent] {
+    let enabledCalendars = settings.enabledCalendars
+
+    return try await withThrowingTaskGroup(of: (String, Result<[CalendarEvent], Error>).self) { group in
+        for calendarId in enabledCalendars {
+            group.addTask {
+                do {
+                    let events = try await self.syncCalendar(calendarId)
+                    return (calendarId, .success(events))
+                } catch {
+                    return (calendarId, .failure(error))
+                }
+            }
+        }
+
+        var allEvents: [CalendarEvent] = []
+        var failures: [(String, Error)] = []
+
+        for try await (calendarId, result) in group {
+            switch result {
+            case .success(let events):
+                allEvents.append(contentsOf: events)
+                await healthTracker.markSuccess(calendarId)
+            case .failure(let error):
+                failures.append((calendarId, error))
+                await healthTracker.markFailure(calendarId, error)
+            }
+        }
+
+        // Log failures but don't throw if we got some events
+        if !failures.isEmpty {
+            logger.warning("Partial sync failure", metadata: ["failures": "\(failures)"])
+        }
+
+        return allEvents
+    }
+}
+```
+
+**Benefits:**
+- All calendar fetches run concurrently
+- Single calendar failure doesn't abort others
+- Automatic cancellation if app terminates mid-sync
+- Clear aggregation of results and errors
+
 **Adaptive polling intervals:**
````

---

## 10. Security Improvement: Token Encryption at Rest

### Issue
The design stores OAuth tokens in Keychain, which is good, but doesn't mention additional encryption for defense in depth.

### Analysis
While Keychain is secure, adding application-level encryption provides defense against Keychain extraction attacks (which have existed historically).

### Rationale
- Defense in depth
- Protects against Keychain vulnerabilities
- Minimal performance overhead
- Industry best practice for sensitive tokens

### Diff

````diff
 ### Security Configuration

 - **OAuth Scope:** `calendar.readonly` (minimal permissions)
 - **Hardened Runtime:** Enabled
 - **App Sandbox:** Enabled with network + keychain entitlements
 - **Credentials:** Client secret and tokens stored in Keychain only (never on disk)
+- **Token encryption:** Additional AES-256 encryption before Keychain storage
+
+### Token Storage Implementation
+
+```swift
+final class KeychainManager {
+    private let encryptionKey: SymmetricKey
+
+    init() {
+        // Derive key from hardware-bound identifier
+        // Uses Secure Enclave on supported hardware
+        encryptionKey = deriveEncryptionKey()
+    }
+
+    func storeToken(_ token: OAuthToken) throws {
+        let data = try JSONEncoder().encode(token)
+        let encrypted = try AES.GCM.seal(data, using: encryptionKey)
+        try keychain.set(encrypted.combined!, forKey: "oauth_token")
+    }
+
+    func retrieveToken() throws -> OAuthToken? {
+        guard let encrypted = try keychain.getData("oauth_token") else {
+            return nil
+        }
+        let box = try AES.GCM.SealedBox(combined: encrypted)
+        let decrypted = try AES.GCM.open(box, using: encryptionKey)
+        return try JSONDecoder().decode(OAuthToken.self, from: decrypted)
+    }
+}
+```
+
+**Key derivation:**
+- Uses `kSecAttrTokenIDSecureEnclave` where available
+- Falls back to device-specific identifier hash
+- Key never leaves device memory
````

---

## 11. UX Improvement: Meeting Context in Alerts

### Issue
Alerts only show meeting title and time. Users often need more context to decide priority.

### Analysis
A meeting titled "Sync" means nothing. Showing attendees and your response status helps users make quick triage decisions.

### Rationale
- Better decision-making from alerts
- Reduces need to open calendar
- Small implementation cost, high information value

### Diff

````diff
 **Single meeting modal:**
 ```
 ┌─────────────────────────────────────┐
 │  Meeting in 10 minutes              │
 │                                     │
 │  Weekly Team Standup                │
 │  10:00 AM - 10:30 AM                │
+│  👥 8 attendees · You're organizing │
 │                                     │
-│  [Join Meeting]  [Snooze ▾]  [Dismiss]│
+│  [Join Meeting]  [Snooze ▾]  [Reschedule]  [✕]│
 └─────────────────────────────────────┘
 ```

+**Context line variants:**
+| Scenario | Display |
+|----------|---------|
+| You're organizer, 8 attendees | 👥 8 attendees · You're organizing |
+| You're attendee, accepted | 👥 5 attendees · Accepted |
+| You're attendee, tentative | 👥 5 attendees · Tentative ⚠️ |
+| You're optional attendee | 👥 5 attendees · Optional |
+| 1:1 meeting | 👤 1:1 with Sarah Chen |
+| Interview (detected) | 👤 Interview with Alex Kim |
+
+**Implementation:**
+- Parse `attendees[]` from event response
+- Store attendee count and your response status in `CalendarEvent`
+- Detect 1:1s (exactly 2 attendees) for special formatting
````

---

## 12. Architecture Improvement: Separate Network and Domain Layers

### Issue
`GoogleCalendarClient` is doing too much—API calls, token management, and response parsing in one place.

### Analysis
Mixing network concerns with domain logic makes testing harder and violates single responsibility. Separating these allows mock API responses for testing.

### Rationale
- Testable without network
- Clearer separation of concerns
- Easier to add retry logic at network layer
- Simpler mocking for unit tests

### Diff

````diff
 ### Project Structure

 ```
 gcal-notifier/
 ├── Sources/
 │   └── GCalNotifier/
-│       ├── Calendar/
-│       │   ├── GoogleCalendarClient.swift # API client, token management
-│       │   ├── SyncEngine.swift           # Incremental sync with syncToken
-│       │   ├── EventCache.swift           # Local persistence layer
-│       │   └── EventModels.swift          # Event, MeetingLink types
+│       ├── Network/
+│       │   ├── HTTPClient.swift           # Generic HTTP with retry/timeout
+│       │   ├── GoogleCalendarAPI.swift    # Raw API calls, returns Data
+│       │   └── APIError.swift             # Network error types
+│       ├── Calendar/
+│       │   ├── CalendarService.swift      # Domain logic, uses API
+│       │   ├── CalendarResponseParser.swift # JSON -> Domain models
+│       │   ├── SyncEngine.swift           # Orchestrates sync strategy
+│       │   ├── EventCache.swift           # Local persistence layer
+│       │   └── EventModels.swift          # Event, MeetingLink types
 ```
+
+**Layer responsibilities:**
+| Layer | Responsibility | Dependencies |
+|-------|---------------|--------------|
+| HTTPClient | Retry, timeout, logging | URLSession |
+| GoogleCalendarAPI | URL construction, headers | HTTPClient, OAuthProvider |
+| CalendarResponseParser | JSON → models | None |
+| CalendarService | Filtering, business logic | API, Parser |
+| SyncEngine | When to sync, caching | CalendarService, EventCache |
````

---

## 13. New Feature: Conflict Detection and Warnings

### Issue
The design handles overlapping alerts but doesn't proactively warn about double-bookings.

### Analysis
Users often don't realize they're double-booked until both alerts fire. Early warning during the day's overview could prevent this.

### Rationale
- Proactive is better than reactive
- Low implementation cost (data is already fetched)
- Meaningful differentiation from basic calendar apps

### Diff

````diff
+### Conflict Detection
+
+**Definition:** Two events conflict if their time ranges overlap and both have video links.
+
+**Detection timing:**
+- On each sync completion
+- Check all events in next 24 hours
+
+**Conflict notification:**
+- Show in menu bar: `⚠️ 2 conflicts today`
+- List conflicts in menu dropdown
+- Optional macOS notification on first detection
+
+**Menu display:**
+```
+┌─────────────────────────────────────┐
+│  ⚠️ Schedule Conflict               │
+│  ────────────────────────────────── │
+│  10:00 - 11:00                      │
+│    • Weekly Standup                 │
+│    • Client Call                    │
+│  ────────────────────────────────── │
+│  Today's Meetings                   │
+│  ...                                │
+└─────────────────────────────────────┘
+```
+
+**Alert behavior for conflicting meetings:**
+- Combined alert shows both meetings
+- Indicates "Conflicting meetings" in header
+- User must choose which to join (or dismiss both)
````

---

## 14. Performance Improvement: Debounced Status Item Updates

### Issue
The design specifies frequent timer-based updates (every 5 seconds when < 2 min away) which can cause UI jank.

### Analysis
Updating `NSStatusItem` text triggers layout recalculation. Rapid updates can cause visible flickering, especially with variable-width countdown strings.

### Rationale
- Smoother visual experience
- Reduced CPU usage
- Prevents layout thrashing

### Diff

````diff
 **Update frequency:**

 | Time to Meeting | Update Interval |
 |-----------------|-----------------|
 | > 60 minutes | Every 5 minutes |
 | 10-60 minutes | Every minute |
-| 2-10 minutes | Every 15 seconds |
-| < 2 minutes | Every 5 seconds |
+| 2-10 minutes | Every 30 seconds |
+| < 2 minutes | Every 10 seconds |

-Use a single `Timer` that adjusts its interval based on time to next event.
+**Implementation details:**
+- Use a single `Timer` that adjusts its interval based on time to next event
+- Only update status item text if value actually changed
+- Use fixed-width font or minimum width to prevent layout shifts
+- Debounce rapid sequential updates (coalesce within 500ms)
+
+```swift
+func updateStatusItemIfNeeded(_ newText: String) {
+    guard newText != currentText else { return }
+
+    // Use attributedTitle with monospace digits for stable width
+    let attributes: [NSAttributedString.Key: Any] = [
+        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
+    ]
+    statusItem.button?.attributedTitle = NSAttributedString(
+        string: newText,
+        attributes: attributes
+    )
+    currentText = newText
+}
+```
````

---

## 15. Robustness Improvement: Explicit State Machine for Auth

### Issue
Auth state is implicit (check for tokens → authenticated). Complex flows like re-auth after revocation aren't clearly defined.

### Analysis
OAuth has many states: unauthenticated, authenticating, authenticated, token expired, refresh failed, credentials invalid. Handling these implicitly leads to edge case bugs.

### Rationale
- Prevents impossible state combinations
- Clear handling for each transition
- Easier debugging
- Better user feedback

### Diff

````diff
+### Authentication State Machine
+
+```swift
+enum AuthState: Equatable {
+    case unconfigured          // No client credentials entered
+    case configured            // Has credentials, not authenticated
+    case authenticating        // OAuth flow in progress
+    case authenticated(expiresAt: Date)  // Valid tokens
+    case refreshing            // Token refresh in progress
+    case expired               // Access token expired, will auto-refresh
+    case invalid               // Refresh failed, needs re-auth
+    case error(AuthError)      // Configuration or other error
+}
+
+enum AuthEvent {
+    case credentialsEntered
+    case signInStarted
+    case signInSucceeded(tokens: OAuthTokens)
+    case signInFailed(Error)
+    case tokenExpired
+    case refreshStarted
+    case refreshSucceeded(tokens: OAuthTokens)
+    case refreshFailed(Error)
+    case signedOut
+    case credentialsCleared
+}
+```
+
+**State transitions:**
+```
+unconfigured --[credentialsEntered]--> configured
+configured --[signInStarted]--> authenticating
+authenticating --[signInSucceeded]--> authenticated
+authenticating --[signInFailed]--> configured
+authenticated --[tokenExpired]--> expired
+expired --[refreshStarted]--> refreshing
+refreshing --[refreshSucceeded]--> authenticated
+refreshing --[refreshFailed]--> invalid
+invalid --[signInStarted]--> authenticating
+* --[signedOut]--> configured
+* --[credentialsCleared]--> unconfigured
+```
+
+**UI indicators per state:**
+| State | Menu Icon | Menu Text |
+|-------|-----------|-----------|
+| unconfigured | 🔑 | Setup Required |
+| configured | 🔑 | Sign In Required |
+| authenticating | ⏳ | Signing in... |
+| authenticated | 📅 | [normal countdown] |
+| refreshing | 📅 | [normal, silent] |
+| expired | 📅 | [normal, auto-refresh] |
+| invalid | 🔑 | Re-authentication Required |
+| error | ⚠️ | Configuration Error |
````

---

## 16. New Feature: Focus Mode Integration

### Issue
No integration with macOS Focus modes, which are increasingly central to how people manage attention.

### Analysis
macOS Focus can be used to suppress alerts during specific activities. Rather than fighting this, integrate with it—or allow users to configure different alert behavior per Focus mode.

### Rationale
- Modern macOS integration
- Respects user's attention preferences
- Provides smart defaults for common Focus modes

### Diff

````diff
+### Focus Mode Integration
+
+Detect and respond to macOS Focus modes:
+
+```swift
+import FocusFilter
+
+// Check current Focus state
+let status = await NotificationCenter.default.focusStatus
+```
+
+**Behavior by Focus mode:**
+| Focus Mode | Default Behavior | Configurable |
+|------------|-----------------|--------------|
+| Do Not Disturb | Sound only, no modal | Yes |
+| Sleep | No alerts | No |
+| Work | Full alerts | Yes |
+| Personal | Full alerts | Yes |
+| Custom | User configured | Yes |
+
+**Settings addition:**
+```swift
+struct FocusModeSettings: Codable {
+    var focusMode: String  // System Focus identifier
+    var alertBehavior: AlertBehavior
+
+    enum AlertBehavior: String, Codable {
+        case full           // Modal + sound
+        case soundOnly      // Sound, no modal
+        case badgeOnly      // Menu bar badge only
+        case suppress       // No alerts
+    }
+}
+
+@AppStorage("focusModeSettingsJSON") var focusModeSettingsJSON: String = "[]"
+```
+
+**Note:** Requires macOS 15+ for full Focus Filter API. Graceful degradation on older versions.
````

---

## 17. Implementation Order Revision

### Issue
The current implementation order puts filtering late (phase 8), but filtering is needed for meaningful testing of alerts.

### Analysis
Testing alerts without filtering means every event triggers alerts during development. Having basic filtering early makes the development experience better.

### Diff

````diff
 ## Implementation Order

 | Phase | Components | Description |
 |-------|------------|-------------|
 | 1 | Project scaffold | Package.swift, app entry point, LSUIElement config |
-| 2 | Auth infrastructure | OAuthProvider protocol, GoogleOAuthProvider, KeychainManager |
-| 3 | Data persistence | EventCache, ScheduledAlertsStore, AppStateStore |
-| 4 | Sync engine | GoogleCalendarClient, SyncEngine with syncToken |
-| 5 | Settings | SettingsStore (with JSON array handling), basic PreferencesView |
-| 6 | Menu bar UI | StatusItemController, MenuContentView, countdown display |
-| 7 | Alert engine | AlertEngine state machine, AlertWindowController, SoundPlayer |
-| 8 | Filtering | Calendar selection, blocked/force keywords |
-| 9 | Advanced features | Snooze, global shortcuts, back-to-back handling |
-| 10 | Polish | Diagnostics panel, screen share detection, error handling edge cases |
-| 11 | Launch at login | SMAppService integration |
+| 2 | Auth infrastructure | OAuthProvider protocol, GoogleOAuthProvider, KeychainManager, AuthState machine |
+| 3 | Network layer | HTTPClient, GoogleCalendarAPI, response parsing |
+| 4 | Data persistence | EventCache, ScheduledAlertsStore, AppStateStore |
+| 5 | Settings + Basic Filtering | SettingsStore, calendar enable/disable, blocked keywords |
+| 6 | Sync engine | CalendarService, SyncEngine with syncToken |
+| 7 | Menu bar UI | StatusItemController, MenuContentView, countdown display |
+| 8 | Alert engine | AlertEngine state machine, UNUserNotificationCenter scheduling |
+| 9 | Alert UI | AlertWindowController, SoundPlayer |
+| 10 | Advanced filtering | Force keywords, prep time rules |
+| 11 | Advanced alerts | Snooze, combined modals, back-to-back handling |
+| 12 | Global shortcuts | KeyboardShortcuts integration |
+| 13 | Polish | Diagnostics panel, screen share detection, conflict detection |
+| 14 | Launch at login | SMAppService integration |

-**Rationale:** Auth + storage foundations first, then sync engine rides on stable data layer, then UI, then advanced features.
+**Rationale:**
+- Auth with explicit state machine prevents edge case bugs
+- Network layer separation enables testing without live API
+- Early filtering improves development experience
+- Alert scheduling (system notifications) before UI allows background testing
+- Advanced features after core loop is solid
````

---

## Summary of Proposed Changes

| # | Category | Change | Impact |
|---|----------|--------|--------|
| 1 | Architecture | UNUserNotificationCenter for scheduling | High reliability |
| 2 | Reliability | Single instance enforcement | Prevents bugs |
| 3 | Feature | Prep time rules | Power user value |
| 4 | Architecture | Dependency injection container | Testability |
| 5 | Reliability | Per-calendar health tracking | Graceful degradation |
| 6 | Feature | Reschedule button | Workflow improvement |
| 7 | Performance | Lazy calendar list loading | Faster startup |
| 8 | Feature | Post-meeting quick actions | Workflow completion |
| 9 | Reliability | TaskGroup for concurrent sync | Proper error handling |
| 10 | Security | Token encryption at rest | Defense in depth |
| 11 | UX | Meeting context in alerts | Better decisions |
| 12 | Architecture | Separate network/domain layers | Maintainability |
| 13 | Feature | Conflict detection | Proactive help |
| 14 | Performance | Debounced status updates | Smoother UI |
| 15 | Architecture | Explicit auth state machine | Robustness |
| 16 | Feature | Focus mode integration | Modern macOS |
| 17 | Process | Revised implementation order | Better dev experience |

---

## Priority Recommendations

### Must Have (v1)
1. UNUserNotificationCenter scheduling (#1)
2. Single instance enforcement (#2)
3. Dependency injection (#4)
4. Explicit auth state machine (#15)
5. Separate network/domain layers (#12)

### Should Have (v1)
6. Per-calendar health tracking (#5)
7. TaskGroup for sync (#9)
8. Meeting context in alerts (#11)
9. Debounced status updates (#14)
10. Revised implementation order (#17)

### Nice to Have (v1.x)
11. Prep time rules (#3)
12. Reschedule button (#6)
13. Lazy calendar list loading (#7)
14. Conflict detection (#13)
15. Token encryption (#10)

### Future (v2)
16. Post-meeting quick actions (#8)
17. Focus mode integration (#16)
