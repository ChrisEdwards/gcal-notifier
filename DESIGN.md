# gcal-notifier Design

macOS menu bar app that provides aggressive, unmissable meeting reminders via Google Calendar API.

## Problem

Google Calendar notifications are easily missed. Slack notification overload makes calendar alerts blend into the noise. Users miss meetings despite having reminders enabled.

## Solution

A dedicated menu bar app that:
- Shows a countdown to your next meeting with a video link
- Fires two-stage modal alerts (configurable timing)
- Plays distinctive custom sounds that train your brain to recognize "meeting alert"
- Provides one-click "Join Meeting" from the alert modal or global hotkey
- Filters out non-meetings automatically (no video link = no alert)
- Allows manual filtering via calendar selection, keyword blocklist, and force-alert keywords
- Survives restarts, sleep, and network interruptions with local persistence

## Target Platform

- macOS 15+ (Sequoia)
- Personal use initially (no App Store distribution)
- User provides their own Google Cloud OAuth credentials

## Non-Goals (v1)

- iOS/watchOS companion apps
- Multiple Google account support
- Integration with other calendar providers (Outlook, etc.)
- App Store distribution / built-in OAuth credentials
- Push notifications via webhooks (requires public HTTPS endpoint)
- Calendar event creation (read-only is simpler and safer)
- Per-meeting custom settings
- Slack status integration

---

## Architecture

### Tech Stack

- **Language:** Swift 6 with SwiftUI
- **Build:** Swift Package Manager
- **Target:** macOS 15+ (Sequoia)
- **Patterns:** `@Observable` macro, Swift concurrency, SwiftUI lifecycle

### Dependencies

| Package | Purpose |
|---------|---------|
| KeyboardShortcuts (sindresorhus) | Global hotkey for "Join Next Meeting" |
| MenuBarExtraAccess (orchetect) | Menu bar extra access from SwiftUI |

No Sparkle or external logging libraries needed (OSLog is native).

### Security Configuration

- **OAuth Scope:** `calendar.readonly` (minimal permissions)
- **Hardened Runtime:** Enabled
- **App Sandbox:** Enabled with network + keychain entitlements
- **Credentials:** Client secret and tokens stored in Keychain only (never on disk)
- **Keychain Service:** Use explicit `kSecAttrService` = `com.gcal-notifier.auth` for consistent access across builds

### Single Instance Enforcement

Prevent duplicate instances (causes duplicate alerts, cache corruption):

```swift
// In AppDelegate.applicationDidFinishLaunching
let running = NSRunningApplication.runningApplications(
    withBundleIdentifier: Bundle.main.bundleIdentifier!
)
if running.count > 1 {
    NSApp.terminate(nil)
}
```

### Project Structure

Two-target architecture: Core (testable, no UI dependencies) + Main (UI/system integration):

```
gcal-notifier/
├── Sources/
│   ├── GCalNotifier/                      # Main app (thin UI layer)
│   │   ├── GCalNotifierApp.swift          # @main entry, SwiftUI App
│   │   ├── AppDelegate.swift              # NSApplicationDelegate, status item setup
│   │   ├── MenuBar/
│   │   │   ├── StatusItemController.swift # NSStatusItem management
│   │   │   └── MenuContentView.swift      # SwiftUI menu content
│   │   ├── Alerts/
│   │   │   ├── AlertWindowController.swift# Modal window management
│   │   │   └── SoundPlayer.swift          # AVFoundation audio playback
│   │   ├── Settings/
│   │   │   ├── PreferencesView.swift      # SwiftUI settings window
│   │   │   └── OAuthSetupView.swift       # Credential configuration
│   │   └── Resources/
│   │       └── Sounds/                    # Built-in alert sounds
│   │
│   └── GCalNotifierCore/                  # Shared library (testable, no UI)
│       ├── Auth/
│       │   ├── OAuthProvider.swift        # Protocol for OAuth abstraction
│       │   ├── GoogleOAuthProvider.swift  # Google-specific implementation
│       │   └── KeychainManager.swift      # Secure credential storage
│       ├── Calendar/
│       │   ├── GoogleCalendarClient.swift # API client, token management
│       │   ├── SyncEngine.swift           # Incremental sync with syncToken
│       │   ├── EventCache.swift           # Local persistence layer
│       │   └── EventModels.swift          # Event, MeetingLink types
│       ├── Alerts/
│       │   └── AlertEngine.swift          # Central alert state machine
│       ├── Settings/
│       │   └── SettingsStore.swift        # @Observable preferences
│       ├── Data/
│       │   ├── AppStateStore.swift        # Disk-backed application state
│       │   └── ScheduledAlertsStore.swift # Persisted alert schedule
│       └── Errors/
│           └── CalendarError.swift        # Typed error definitions
│
├── Tests/
│   └── GCalNotifierTests/                 # Unit tests
│
├── Package.swift
└── README.md
```

### App Configuration

- `LSUIElement = true` in Info.plist (no Dock icon)
- Menu bar only presence
- Launch at login enabled by default via `SMAppService`

---

## Google Calendar Integration

### Authentication Flow

1. User creates a Google Cloud project and enables Calendar API
2. User creates OAuth 2.0 credentials (Desktop app type)
3. User pastes Client ID and Client Secret into gcal-notifier Settings
4. App opens browser for Google sign-in, receives authorization code via localhost redirect
5. App exchanges code for access + refresh tokens, stores in macOS Keychain
6. Tokens auto-refresh proactively (before expiry, not after 401)
7. User only re-authenticates if refresh token is revoked

### OAuth Provider Abstraction

```swift
protocol OAuthProvider {
    var isAuthenticated: Bool { get }
    func authenticate() async throws
    func getAccessToken() async throws -> String
    func signOut() async throws
}

// Allows future built-in credentials without refactoring
class GoogleOAuthProvider: OAuthProvider {
    init(clientId: String, clientSecret: String)
}
```

### Authentication State Machine

Explicit states prevent edge case bugs:

```swift
enum AuthState: Equatable {
    case unconfigured       // No credentials entered
    case configured         // Has credentials, not signed in
    case authenticating     // OAuth flow in progress
    case authenticated      // Valid tokens
    case expired            // Token expired, will auto-refresh
    case invalid            // Refresh failed, needs re-auth
}

// State transitions
// unconfigured → configured (credentials entered)
// configured → authenticating (sign-in started)
// authenticating → authenticated (success) or configured (failed)
// authenticated → expired (token expires)
// expired → authenticated (refresh success) or invalid (refresh failed)
// invalid → authenticating (user re-authenticates)
```

**UI indicators per state:**
| State | Menu Icon | Action |
|-------|-----------|--------|
| unconfigured | 🔑 | Open Settings |
| configured | 🔑 | Prompt sign-in |
| authenticating | ⏳ | Show "Signing in..." |
| authenticated | 📅 | Normal operation |
| expired | 📅 | Auto-refresh (invisible to user) |
| invalid | 🔑 | Prompt re-auth |

### API Usage

**Initial sync (full fetch):**
```
GET https://www.googleapis.com/calendar/v3/calendars/{calendarId}/events
  ?timeMin={now}
  &timeMax={now + 24h}
  &singleEvents=true
  &orderBy=startTime
  &timeZone={user's current time zone}
```

**Incremental sync (subsequent fetches):**
```
GET https://www.googleapis.com/calendar/v3/calendars/{calendarId}/events
  ?syncToken={stored_token}
  &timeZone={user's current time zone}
```

**Sync token management:**
- Store `nextSyncToken` per calendar after each successful fetch
- If API returns `410 Gone`: clear sync token, perform full re-sync
- Incremental sync returns only new/modified/deleted events
- Explicitly detects deleted events (no need to diff arrays)

**Calendar list endpoint:**
```
GET https://www.googleapis.com/calendar/v3/users/me/calendarList
```

### Sync Strategy

**Adaptive polling intervals:**

| Condition | Poll Interval |
|-----------|---------------|
| No meetings in next 2 hours | Every 15 minutes |
| Meeting within 1 hour | Every 5 minutes |
| Meeting within 10 minutes | Every 1 minute |

**Additional refresh triggers:**
- On wake from sleep: immediate refresh
- After dismissing an alert: refresh to catch changes
- On time zone change: immediate refresh
- Manual "Refresh Now" from menu
- On sync token invalidation (410 response): full re-sync

**Rate limit handling:**
- Jittered polling with exponential backoff on 403 errors
- Show warning in menu when rate limited

**Multi-calendar sync with TaskGroup:**

```swift
func syncAllCalendars() async -> [CalendarEvent] {
    await withTaskGroup(of: (String, Result<[CalendarEvent], Error>).self) { group in
        for calendarId in enabledCalendars {
            group.addTask { await self.syncCalendar(calendarId) }
        }

        var allEvents: [CalendarEvent] = []
        for await (calendarId, result) in group {
            switch result {
            case .success(let events):
                allEvents.append(contentsOf: events)
                await healthTracker.markSuccess(calendarId)
            case .failure(let error):
                await healthTracker.markFailure(calendarId, error)
            }
        }
        return allEvents
    }
}
```

**Per-calendar health tracking:**

```swift
enum CalendarHealth { case healthy, failing, disabled }
```

| Status | Behavior |
|--------|----------|
| healthy | Normal polling |
| failing | 4x slower polling, yellow indicator in menu |
| disabled | No polling until user re-enables |

A calendar becomes `failing` after 3 consecutive errors. User can still see events from healthy calendars even when one calendar fails.

**Persistence:** Only `disabled` state is persisted (user explicitly disabled). `failing` resets to `healthy` on app restart (allows retry after transient network issues).

### Time Zone Handling

- Fetch user's current time zone via `TimeZone.current.identifier`
- Pass to API to get times in local zone
- Store events with UTC timestamps internally
- Display times in user's current zone (handles travel scenarios)
- Subscribe to `NSSystemTimeZoneDidChange` notification
- Re-fetch events if time zone changes

### Meeting Link Extraction

Google Calendar stores video links in multiple places. Extract in priority order:

1. `conferenceData.entryPoints[].uri` - Structured Meet/Zoom/Teams data
2. `hangoutLink` - Legacy Google Meet field
3. `location` field - URL scan for video platforms
4. `description` field - Fallback regex scan
5. `attachments[].fileUrl` - Attachment URLs

**Canonicalization:**
- Deduplicate when same link appears in multiple fields
- Normalize URLs (remove tracking parameters where safe)

**Supported video platforms:**
- Google Meet (`meet.google.com`)
- Zoom (`zoom.us`, `*.zoom.us`)
- Microsoft Teams (`teams.microsoft.com`, `teams.live.com`)
- Webex (`*.webex.com`)
- Slack Huddles (`slack.com/huddle`)

Unknown video URLs in `conferenceData` are still used (covers niche platforms without hardcoding).

---

## Alert System

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
    func reconcileOnRelaunch()  // Only needed for app restart

    // State
    var scheduledAlerts: [ScheduledAlert]
    var acknowledgedEvents: Set<String>
    private var pendingNotifications: [String: String] = [:]  // eventId → notificationId
}
```

**Key properties:**
- Uses `UNUserNotificationCenter` for timing (handles sleep/wake, DST, NTP corrections)
- Persists scheduled alerts to disk
- Reconciles on relaunch only (system handles wake scenarios)
- Guarantees "exactly once" alert delivery
- Cancels/reschedules on event mutation
- Tracks acknowledgment state per event

**System notification integration:**
- Register custom notification category with hidden presentation
- `UNCalendarNotificationTrigger` schedules alerts at exact times
- Delegate intercepts delivery and shows custom modal instead
- System handles timing even during sleep - no Timer drift

**Task cancellation for deleted events:**

When events are removed, cancel their scheduled alerts:

```swift
func reconcile(newEvents: [CalendarEvent]) {
    let newIds = Set(newEvents.map { $0.id })

    // Cancel alerts for removed events
    for (eventId, notificationId) in pendingNotifications {
        if !newIds.contains(eventId) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [notificationId]
            )
            pendingNotifications.removeValue(forKey: eventId)
        }
    }

    // Schedule alerts for new/modified events...
}
```

### Two-Stage Alerts

| Stage | Default | Range | Purpose |
|-------|---------|-------|---------|
| 1 | 10 min | 1-60 min | Early warning - wrap up what you're doing |
| 2 | 2 min | 1-30 min | Urgent reminder - join now |

- Each stage fires a modal window + sound
- Set to 0 to disable a stage
- Stage 1 must be greater than stage 2
- Both stages equally aggressive (modal + sound)

### Modal Window

A floating `NSPanel` with properties:
- `level: .floating` - Appears above other windows (when not suppressed)
- `styleMask: [.titled, .closable]` - Standard window chrome
- `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]` - Visible on all desktops

**Single meeting modal:**
```
┌─────────────────────────────────────┐
│  Meeting in 10 minutes              │
│                                     │
│  Weekly Team Standup                │
│  10:00 AM - 10:30 AM                │
│  👥 8 attendees · You're organizing │
│                                     │
│  [Join]  [Snooze ▾]  [Open in Cal]  [✕]│
└─────────────────────────────────────┘
```

**Meeting context line variants:**
| Scenario | Display |
|----------|---------|
| You're organizer | 👥 8 attendees · You're organizing |
| You accepted | 👥 5 attendees · Accepted |
| You're tentative | 👥 5 attendees · Tentative ⚠️ |
| 1:1 meeting | 👤 1:1 with Sarah Chen |
| Interview | 👤 Interview with Alex Kim |

**Combined modal (multiple meetings):**
```
┌─────────────────────────────────────┐
│  2 meetings starting soon           │
│                                     │
│  ▶ Weekly Standup           10:00   │
│  ▶ 1:1 with Sarah           10:00   │
│                                     │
│  [Join Standup]  [Join 1:1]  [Dismiss All]│
└─────────────────────────────────────┘
```

**Button actions:**
- **Join:** Opens meeting URL via `NSWorkspace.shared.open(url)`, closes window
- **Snooze:** Dropdown with options (1 min, 3 min, 5 min). Reschedules alert.
- **Open in Cal:** Opens event in Google Calendar web UI. User can reschedule from there.
- **✕ (Dismiss):** Closes window, marks event acknowledged (no further alerts for this event)

**Snooze behavior:**
- Snooze replaces remaining scheduled alerts for this event
- Snoozed alert shows context ("Snoozed from 10-min warning")
- Cannot snooze past meeting start time
- If meeting starts while snoozed, shows "Meeting started!" alert

### Presentation Mode & DND Awareness

| Condition | Behavior |
|-----------|----------|
| Normal | Full modal + sound |
| Screen sharing active | Suppress modal, menu bar pulse + sound only |
| Screen mirroring active | Suppress modal, menu bar pulse + sound only |
| Do Not Disturb enabled | Sound only (optionally suppress), badge icon |
| In another meeting | See "Back-to-Back Meeting Handling" |

**Screen sharing detection:**
- Use `CGDisplayStream` or `SCShareableContent` to detect active screen sharing
- Check `CGDisplayIsOnline` and display mirroring status

### Sound Playback

`SoundPlayer` uses AVFoundation:
- Load sound from bundle (built-in) or user-specified file path
- Play on alert fire, before showing modal
- Respect system volume
- Sound plays once for combined alerts (not per meeting)

**Sound options:**
- 2-3 built-in distinctive sounds (not standard macOS sounds)
- Custom sound file support (.mp3, .wav, .aiff)
- Separate sound selection for each alert stage
- Test button in preferences

### Back-to-Back Meeting Handling

When meetings are back-to-back (next meeting starts within 5 minutes of previous ending):

1. **Downgraded first alert:** If user is in another meeting, the 10-minute warning becomes a passive notification instead of modal:
   - Plays a subtle sound (different from urgent alert)
   - Shows macOS notification banner: "Up Next: [Meeting Name] in 10m"
   - Does not steal keyboard focus
   - *Rationale: Suppressing entirely risks missing the meeting if current one runs over*
2. **Transition alert:** Show "Next meeting starting" at end of current meeting (full modal)
3. **Menu bar indicator:** Show `📅 12m → 5m` format (current ends in 12m, next in 5m)

**Definition of "in a meeting":** Current time is between start and end of a meeting with a video link.

---

## Menu Bar UI

### Status Item Display

Format: `[icon] [countdown]`

| State | Display |
|-------|---------|
| Next meeting in 32 minutes | `📅 32m` |
| Next meeting in 1 hour 15 minutes | `📅 1h 15m` |
| In meeting, next in 5 minutes | `📅 12m → 5m` |
| Within alert window (< 10 min) | `🔔 8m` |
| Alert acknowledged | `✅ 5m` |
| No upcoming meetings with video links | `📅 --` |
| Offline | `⚠️ --` |
| OAuth error | `🔑` |

**Update frequency:**

| Time to Meeting | Update Interval |
|-----------------|-----------------|
| > 60 minutes | Every 5 minutes |
| 10-60 minutes | Every minute |
| 2-10 minutes | Every 30 seconds |
| < 2 minutes | Every 10 seconds |

**Status item update implementation:**
- Single `Timer` that adjusts interval based on time to next event
- Only update text if value actually changed (prevents flickering)
- Use monospace digits for stable width: `NSFont.monospacedDigitSystemFont`

```swift
func updateStatusItemIfNeeded(_ newText: String) {
    guard newText != currentText else { return }
    statusItem.button?.attributedTitle = NSAttributedString(
        string: newText,
        attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)]
    )
    currentText = newText
}
```

### Menu Content

```
┌─────────────────────────────────────┐
│  ▶ Join: Weekly Standup    in 8 min │
│  ────────────────────────────────── │
│  ⚠️ Conflict at 14:00 (2 meetings)  │
│  ────────────────────────────────── │
│  Today's Meetings                   │
│    ✓ Weekly Standup           10:00 │
│    ⚠ 1:1 with Sarah           14:00 │
│    ⚠ Client Call              14:00 │
│    ○ Team Retro (no link)     16:00 │
│  ────────────────────────────────── │
│  ⟳ Refresh Now                      │
│  ⚙ Settings...                      │
│  ────────────────────────────────── │
│  Quit gcal-notifier                 │
└─────────────────────────────────────┘
```

- ✓ = has video link (will alert)
- ○ = no video link (won't alert)
- ⚠ = conflicting meeting (overlaps with another)
- Click meeting to open its video link directly
- **"▶ Join:" header** is always visible and clickable
  - Opens next meeting's video link immediately
  - Shows meeting title and countdown
  - Disabled/hidden when no upcoming meetings

**Meeting submenu (click meeting to expand):**
- Join Meeting (opens video link)
- Copy Link (to clipboard)
- Open in Calendar (opens event in browser)

### Conflict Detection

Two events conflict if their time ranges overlap and both will trigger alerts (have video links or force-alert keywords).

**Detection:** Check all events in next 24 hours on each sync completion.

**Display:**
- Warning banner in menu: `⚠️ Conflict at 14:00 (2 meetings)`
- Conflicting meetings marked with ⚠ in list
- Combined alert modal shows both and indicates conflict

### Global Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧J (configurable) | Join the next upcoming meeting |
| ⌘⇧D (configurable) | Dismiss currently visible alert |

**Join shortcut behavior:**
- If next meeting is within 30 minutes: opens meeting URL directly
- If next meeting is >30 minutes away: shows confirmation ("Join meeting in 2h 15m?")
- If no upcoming meetings: shows brief notification

---

## Filtering & Configuration

### Settings Storage

```swift
@Observable
final class SettingsStore {
    // Startup
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = true

    // Alert timing (0 = disabled)
    @AppStorage("alertStage1Minutes") var alertStage1Minutes: Int = 10
    @AppStorage("alertStage2Minutes") var alertStage2Minutes: Int = 2

    // Sounds
    @AppStorage("stage1Sound") var stage1Sound: String = "gentle-chime"
    @AppStorage("stage2Sound") var stage2Sound: String = "urgent-tone"
    @AppStorage("customSoundPath") var customSoundPath: String?

    // Filtering (arrays stored as JSON strings)
    @AppStorage("enabledCalendarsJSON") private var enabledCalendarsJSON: String = "[]"
    @AppStorage("blockedKeywordsJSON") private var blockedKeywordsJSON: String = "[]"
    @AppStorage("forceAlertKeywordsJSON") private var forceAlertKeywordsJSON: String = "[\"Interview\", \"IMPORTANT\"]"

    // Computed array accessors
    var enabledCalendars: [String] {
        get { decodeJSON(enabledCalendarsJSON) }
        set { enabledCalendarsJSON = encodeJSON(newValue) }
    }

    var blockedKeywords: [String] {
        get { decodeJSON(blockedKeywordsJSON) }
        set { blockedKeywordsJSON = encodeJSON(newValue) }
    }

    var forceAlertKeywords: [String] {
        get { decodeJSON(forceAlertKeywordsJSON) }
        set { forceAlertKeywordsJSON = encodeJSON(newValue) }
    }

    // Polling
    @AppStorage("basePollingIntervalMinutes") var basePollingIntervalMinutes: Int = 5

    // Presentation mode
    @AppStorage("suppressDuringScreenShare") var suppressDuringScreenShare: Bool = true
    @AppStorage("suppressDuringDND") var suppressDuringDND: Bool = false

    // Global shortcuts
    @AppStorage("joinShortcutEnabled") var joinShortcutEnabled: Bool = true

    // Debug
    @AppStorage("logLevel") var logLevel: String = "info"
}
```

### Preferences Window Tabs

1. **General**
   - Alert timing sliders for each stage (1-60 min, 0 = disabled)
   - Launch at login toggle (uses SMAppService.mainApp)
   - Global keyboard shortcut configuration

2. **Sounds**
   - Sound picker for each stage
   - Custom file selector
   - Test button per stage

3. **Calendars**
   - Checklist of calendars from Google account
   - Toggle each calendar on/off

4. **Filtering**
   - Blocked keywords list (events containing these won't alert)
   - Force-alert keywords list (events containing these always alert, even without video link)
   - Keyword matching applies to title and location fields

5. **Account**
   - OAuth credentials input
   - Sign-in status
   - Sign-out button
   - Last sync time and last error (if any)
   - "Force Full Sync" button

### Filtering Logic

Events must pass filters to trigger alerts:

1. **Not all-day event** (automatic) - All-day events never trigger alerts
   - Detection: `event.start.date` (date only) vs `event.start.dateTime` (timestamp)

2. **Has video link OR force-alert keyword** (automatic/manual)
   - Event has extractable meeting URL, OR
   - Event title/location contains force-alert keyword (e.g., "Interview", "IMPORTANT")

3. **Calendar enabled** (manual) - Event's calendar must be in enabled list

4. **No blocked keywords** (manual) - Event title/location must not contain blocked keywords

**Keyword matching:** Case-insensitive substring match.

**Filter precedence:** Blocked keywords override force-alert keywords.

### Event Prioritization

When multiple meetings have overlapping alert times:
- Prioritize meetings where user is organizer
- Then meetings with more attendees
- Then meetings accepted (vs tentative/no response)
- Show secondary meeting conflicts in combined modal

---

## Data Persistence

### Event Cache

```swift
actor EventCache {
    private let fileURL: URL  // ~/Library/Application Support/gcal-notifier/events.json

    func save(_ events: [CalendarEvent]) async throws
    func load() async throws -> [CalendarEvent]
    func clear() async throws
}
```

**Cache behavior:**
- Update cache after each successful API sync
- Clear cache when user signs out
- On app launch: if last sync > 24 hours ago, clear syncTokens and do full re-sync
- Survives app restarts

### Alert Schedule Persistence

```swift
actor ScheduledAlertsStore {
    private let fileURL: URL  // ~/Library/Application Support/gcal-notifier/alerts.json

    func save(_ alerts: [ScheduledAlert]) async throws
    func load() async throws -> [ScheduledAlert]
}
```

**Scheduled alert includes:**
- Event ID
- Alert stage
- Scheduled fire time
- Snooze count (if snoozed)
- Original alert time (if snoozed)

### Sync State

```swift
struct SyncState: Codable {
    var syncTokens: [String: String]  // calendarId -> syncToken
    var lastFullSync: Date
    var lastIncrementalSync: Date
}
```

---

## Data Flow

### Startup Sequence

1. App launches, `AppDelegate.applicationDidFinishLaunching`
2. Load persisted state:
   - Cached events from disk
   - Scheduled alerts from disk
   - Sync tokens
3. Schedule any pending alerts immediately (from cache)
4. Create `StatusItemController`, display from cache
5. Check for OAuth credentials in Keychain
   - Missing → Show "Setup Required" in menu, open Settings on click
   - Present → Initialize `GoogleCalendarClient` with tokens
6. Start `SyncEngine`, perform incremental sync
7. `AlertEngine` reconciles cached alerts with fresh data

### Event Refresh Cycle

```
SyncEngine (adaptive interval)
    │
    ▼
GoogleCalendarClient.syncEvents(token: syncToken?)
    │
    ▼
Parse response, update syncToken
    │
    ▼
Filter: not all-day event?
    │
    ▼
Filter: has video link OR force-alert keyword?
    │
    ▼
Filter: calendar enabled?
    │
    ▼
Filter: no blocked keywords?
    │
    ▼
Filtered events → EventCache.save()
                → AlertEngine.scheduleAlerts()
                → StatusItemController.updateDisplay()
```

### Alert Trigger Flow

```
AlertEngine evaluates due alerts (wall-clock based)
    │
    ▼
Check suppression conditions (screen share, DND, in meeting)
    │
    ├─ Suppressed → Menu bar pulse + optional sound
    │
    └─ Not suppressed ↓
                      │
                      ▼
                SoundPlayer.play(stageSound)
                      │
                      ▼
                AlertWindowController.show(event, stage)
                      │
                      ▼
        ┌─────────────┼─────────────┐
        │             │             │
    [Join]      [Snooze]      [Dismiss]
        │             │             │
        ▼             ▼             ▼
   Open URL    Reschedule     Mark acknowledged
   Close       alert          Close
```

---

## Error Handling

### OAuth Errors

| Error | Handling |
|-------|----------|
| Token refresh fails | Show 🔑 icon, "Re-authenticate" badge, prompt in Settings |
| Invalid credentials | Clear tokens, return to setup state |
| Network offline | Use cached events, show ⚠️ icon, retry on connectivity |

### Calendar API Errors

| Error | Handling |
|-------|----------|
| Rate limited (403) | Exponential backoff with jitter, show warning in menu |
| Sync token invalid (410) | Clear sync token, perform full re-sync |
| Calendar not found | Remove from enabled list, notify user |
| Partial failure | Show events that succeeded, log failures |

### Alert Edge Cases

| Scenario | Handling |
|----------|----------|
| Meeting deleted while alert pending | Cancel alert |
| Meeting time changed | Reschedule alerts on next sync |
| Meeting starts before alert fires | Skip alerts for events starting within 1 minute |
| Multiple meetings at same time | Combined modal (see above) |
| App restart with pending alerts | Load from persistence, reconcile |
| Missed alert during sleep | Show "Meeting started!" if < 5 min ago |

### Wake from Sleep

- Subscribe to `NSWorkspace.didWakeNotification`
- Immediate calendar refresh (incremental sync)
- Alert timing handled automatically by `UNUserNotificationCenter` (survives sleep)
- AlertEngine checks for missed meetings:
  - If meeting started < 5 min ago, show "Meeting started!" alert
  - Otherwise, no action needed - system notifications handle timing correctly

---

## Logging

Use `OSLog` with subsystem `com.gcal-notifier`. Logs appear in Console.app.

```swift
import OSLog
private let logger = Logger(subsystem: "com.gcal-notifier", category: "sync")
logger.info("Sync completed: \(events.count) events")
logger.error("Auth failed: \(error.localizedDescription)")
```

**Enabling debug logs:**
- `defaults write com.gcal-notifier logLevel debug`
- Or hold Option while clicking "Refresh Now"

No custom log files or rotation - Console.app handles this.

---

## First Launch Experience

1. Menu shows "Setup Required - Click to configure"
2. Settings opens to Account tab
3. Inline instructions with links:
   - Create Google Cloud project
   - Enable Calendar API
   - Create OAuth credentials (Desktop app)
   - Paste Client ID and Secret
4. "Sign In" button initiates OAuth flow
5. On success: fetch calendars, enable all by default
6. Show "You're all set!" confirmation

---

## Implementation Order

| Phase | Components | Description |
|-------|------------|-------------|
| 1 | Project scaffold | Package.swift, app entry point, LSUIElement, single instance check |
| 2 | Auth infrastructure | OAuthProvider, GoogleOAuthProvider, KeychainManager, AuthState machine |
| 3 | Data persistence | EventCache, ScheduledAlertsStore, AppStateStore |
| 4 | Settings + Filtering | SettingsStore, calendar enable/disable, blocked keywords (early for dev experience) |
| 5 | Sync engine | GoogleCalendarClient, SyncEngine with syncToken, TaskGroup, per-calendar health |
| 6 | Menu bar UI | StatusItemController, countdown, debounced updates |
| 7 | Alert engine | AlertEngine with UNUserNotificationCenter scheduling |
| 8 | Alert UI | AlertWindowController, SoundPlayer, modal with context |
| 9 | Menu features | Meeting list, conflict detection, context menus |
| 10 | Advanced alerts | Snooze, combined modals, back-to-back handling |
| 11 | Global shortcuts | KeyboardShortcuts integration |
| 12 | Polish | Screen share detection, Open in Calendar button |
| 13 | Launch at login | SMAppService integration |

**Rationale:**
- Auth with state machine prevents edge case bugs
- Early filtering improves development experience (not every event triggers alerts)
- UNUserNotificationCenter before UI allows reliable background testing
- Advanced features after core loop is solid

---

## Implementation Risk Notes

1. **OAuth token refresh** - Ensure refresh happens proactively (before expiry), not reactively (after 401)
2. **Keychain access** - Use explicit `kSecAttrService`; test across debug/release builds
3. **NSPanel behavior** - Verify floating panel across Spaces and full-screen apps
4. **SMAppService** - Requires proper entitlements; may need notarization even for personal use
5. **Screen share detection** - API availability varies by macOS version
6. **@AppStorage limitations** - Arrays require JSON encoding; watch for sync issues
7. **UNUserNotificationCenter permission** - If user denies notification permission, alerts won't fire. Request permission on first launch with clear explanation. If denied, show warning in menu but don't build fallback.
8. **TaskGroup cancellation** - Ensure proper cleanup if app terminates mid-sync

---

## Reference Implementation

CodexBar (`../CodexBar`) provides patterns for:
- Swift Package Manager macOS menu bar app structure
- `NSStatusItem` with SwiftUI content
- Keychain credential storage
- Preferences window with tabs
- No-Dock-icon configuration
- Launch at login via SMAppService
