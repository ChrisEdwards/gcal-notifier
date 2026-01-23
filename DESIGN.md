# gcal-notifier Design

macOS menu bar app that provides aggressive, unmissable meeting reminders via Google Calendar API.

## Problem

Google Calendar notifications are easily missed. Slack notification overload makes calendar alerts blend into the noise. Users miss meetings despite having reminders enabled.

## Solution

A dedicated menu bar app that:
- Shows a countdown to your next meeting with a video link
- Fires configurable multi-stage modal alerts with escalating urgency
- Plays distinctive custom sounds that train your brain to recognize "meeting alert"
- Provides one-click "Join Meeting" from the alert modal or global hotkey
- Filters out non-meetings automatically (no video link = no alert)
- Allows manual filtering via calendar selection, keyword blocklist, and force-alert keywords
- Survives restarts, sleep, and network interruptions with local persistence

## Target Platform

- macOS 14+ (Sonoma)
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
- **Target:** macOS 14+ (Sonoma)
- **Patterns:** `@Observable` macro, Swift concurrency, SwiftUI lifecycle

### Dependencies

| Package | Purpose |
|---------|---------|
| KeyboardShortcuts (sindresorhus) | Global hotkey for "Join Next Meeting" |
| swift-log (Apple) | Structured logging |

No Sparkle needed initially (personal use, manual updates).

### Security Configuration

- **OAuth Scope:** `calendar.readonly` (minimal permissions)
- **Hardened Runtime:** Enabled
- **App Sandbox:** Enabled with network + keychain entitlements
- **Credentials:** Client secret and tokens stored in Keychain only (never on disk)

### Project Structure

```
gcal-notifier/
├── Sources/
│   └── GCalNotifier/
│       ├── GCalNotifierApp.swift          # @main entry, SwiftUI App
│       ├── AppDelegate.swift              # NSApplicationDelegate, status item setup
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
│       │   ├── AlertEngine.swift          # Central alert state machine
│       │   ├── AlertWindowController.swift# Modal window management
│       │   └── SoundPlayer.swift          # AVFoundation audio playback
│       ├── MenuBar/
│       │   ├── StatusItemController.swift # NSStatusItem management
│       │   └── MenuContentView.swift      # SwiftUI menu content
│       ├── Settings/
│       │   ├── SettingsStore.swift        # @Observable preferences
│       │   ├── PreferencesView.swift      # SwiftUI settings window
│       │   ├── OAuthSetupView.swift       # Credential configuration
│       │   └── DiagnosticsView.swift      # Debug info and log export
│       ├── Data/
│       │   ├── AppStateStore.swift        # Disk-backed application state
│       │   └── ScheduledAlertsStore.swift # Persisted alert schedule
│       └── Resources/
│           └── Sounds/                    # Built-in alert sounds
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

### API Usage

**Initial sync (full fetch):**
```
GET https://www.googleapis.com/calendar/v3/calendars/{calendarId}/events
  ?timeMin={now}
  &timeMax={now + 24h}
  ?singleEvents=true
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
- Full re-sync every 6 hours or on sync invalidation

**Rate limit handling:**
- Jittered polling with exponential backoff on 403 errors
- Show warning in menu when rate limited

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
- Around (`around.co`)
- Tuple (`tuple.app`)
- Discord (`discord.gg`, `discord.com`)
- Whereby (`whereby.com`)
- Loom Live (`loom.com/meet`)

Unknown video URLs in `conferenceData` are still used (future-proofs new platforms).

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
    func reconcileOnWake()
    func reconcileOnRelaunch()

    // State
    var scheduledAlerts: [ScheduledAlert]
    var acknowledgedEvents: Set<String>
}
```

**Key properties:**
- Deterministic scheduling (wall-clock based, not timer drift)
- Persists scheduled alerts to disk
- Reconciles on wake/relaunch
- Guarantees "exactly once" alert delivery
- Cancels/reschedules on event mutation
- Tracks acknowledgment state per event

### Configurable Alert Stages

| Stage | Default | Range | Purpose |
|-------|---------|-------|---------|
| 1 | 10 min | 1-60 min | Early warning - wrap up what you're doing |
| 2 | 2 min | 1-30 min | Urgent reminder - join now |
| 3 | Off | 1-60 min | Optional extra early warning |

- Each enabled stage fires a modal window + sound
- Set to 0 to disable a stage
- Stages must be in descending order (stage 1 > stage 2 > stage 3)
- Both stages equally aggressive by default (modal + sound)

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
│                                     │
│  [Join Meeting]  [Snooze ▾]  [Dismiss]│
└─────────────────────────────────────┘
```

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
- **Join Meeting:** Opens meeting URL via `NSWorkspace.shared.open(url)`, closes window
- **Snooze:** Dropdown with options (1 min, 3 min, 5 min). Reschedules alert.
- **Dismiss:** Closes window, marks event acknowledged (no further alerts for this event)

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

1. **First alert suppression:** Skip the 10-minute warning if user is currently in another meeting
2. **Transition alert:** Show "Next meeting starting" at end of current meeting
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
| Within alert window (< 10 min) | `🔔 8m` (pulses) |
| Alert acknowledged | `✅ 5m` |
| No upcoming meetings with video links | `📅 --` |
| Offline | `⚠️ --` |
| OAuth error | `🔑` |

**Update frequency:**

| Time to Meeting | Update Interval |
|-----------------|-----------------|
| > 60 minutes | Every 5 minutes |
| 10-60 minutes | Every minute |
| 2-10 minutes | Every 15 seconds |
| < 2 minutes | Every 5 seconds |

Use a single `Timer` that adjusts its interval based on time to next event.

### Menu Content

```
┌─────────────────────────────────────┐
│  ▶ Join: Weekly Standup    in 8 min │
│  ────────────────────────────────── │
│  Today's Meetings                   │
│    ✓ Weekly Standup           10:00 │
│    ✓ 1:1 with Sarah           14:00 │
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
- Click meeting to open its video link directly
- **"▶ Join:" header** is always visible and clickable
  - Opens next meeting's video link immediately
  - Shows meeting title and countdown
  - Disabled/hidden when no upcoming meetings

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

    // Alert timing (up to 3 stages, 0 = disabled)
    @AppStorage("alertStage1Minutes") var alertStage1Minutes: Int = 10
    @AppStorage("alertStage2Minutes") var alertStage2Minutes: Int = 2
    @AppStorage("alertStage3Minutes") var alertStage3Minutes: Int = 0

    // Sounds
    @AppStorage("stage1Sound") var stage1Sound: String = "gentle-chime"
    @AppStorage("stage2Sound") var stage2Sound: String = "urgent-tone"
    @AppStorage("stage3Sound") var stage3Sound: String = "gentle-chime"
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

6. **Diagnostics**
   - Last sync time and status
   - Next scheduled poll
   - Token expiry countdown
   - Cache age and event count
   - Last error (if any)
   - "Force Full Sync" button
   - "Export Logs" button

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
- Cache expires after 24 hours (force full re-sync)
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
- AlertEngine reconciles:
  - Cancel alerts for past events
  - Fire "missed" alerts for meetings started < 5 min ago
  - Reschedule upcoming alerts

---

## Logging & Observability

### Log Categories

| Category | Content |
|----------|---------|
| `auth` | OAuth flow, token refresh, credential changes |
| `sync` | API calls, sync token updates, event parsing |
| `alerts` | Scheduling, firing, snoozing, dismissal |
| `ui` | Menu bar updates, modal display, user interactions |
| `lifecycle` | App start/stop, wake/sleep, state persistence |

### Log Levels

| Level | Content |
|-------|---------|
| `debug` | Detailed API responses, timer scheduling, event parsing |
| `info` | OAuth flow steps, successful syncs, alerts fired |
| `warning` | Rate limits, network issues, recoverable errors |
| `error` | Auth failures, critical errors |

**Default level:** `info`

### Enabling Debug Logs

- Hold Option while clicking "Refresh Now" in menu
- Or: `defaults write com.gcal-notifier logLevel debug`

### Log Storage

- Logs written to `~/Library/Logs/gcal-notifier/`
- Daily rotation
- Export via Diagnostics tab in Settings

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
| 1 | Project scaffold | Package.swift, app entry point, LSUIElement config |
| 2 | Auth infrastructure | OAuthProvider protocol, GoogleOAuthProvider, KeychainManager |
| 3 | Data persistence | EventCache, ScheduledAlertsStore, AppStateStore |
| 4 | Sync engine | GoogleCalendarClient, SyncEngine with syncToken |
| 5 | Settings | SettingsStore (with JSON array handling), basic PreferencesView |
| 6 | Menu bar UI | StatusItemController, MenuContentView, countdown display |
| 7 | Alert engine | AlertEngine state machine, AlertWindowController, SoundPlayer |
| 8 | Filtering | Calendar selection, blocked/force keywords |
| 9 | Advanced features | Snooze, global shortcuts, back-to-back handling |
| 10 | Polish | Diagnostics panel, screen share detection, error handling edge cases |
| 11 | Launch at login | SMAppService integration |

**Rationale:** Auth + storage foundations first, then sync engine rides on stable data layer, then UI, then advanced features.

---

## Implementation Risk Notes

1. **OAuth token refresh** - Ensure refresh happens proactively (before expiry), not reactively (after 401)
2. **Keychain access** - Test thoroughly with different macOS security settings
3. **NSPanel behavior** - Verify floating panel across Spaces and full-screen apps
4. **SMAppService** - Requires proper entitlements; may need notarization even for personal use
5. **Screen share detection** - API availability varies by macOS version
6. **@AppStorage limitations** - Arrays require JSON encoding; watch for sync issues

---

## Reference Implementation

CodexBar (`../CodexBar`) provides patterns for:
- Swift Package Manager macOS menu bar app structure
- `NSStatusItem` with SwiftUI content
- Keychain credential storage
- Preferences window with tabs
- Logging infrastructure (swift-log + OSLog)
- No-Dock-icon configuration
- Launch at login via SMAppService
