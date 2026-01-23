# Design Review: gcal-notifier

**Reviewer:** Claude Opus 4.5
**Date:** 2026-01-22
**Document Reviewed:** `docs/DESIGN.md`

## Overview Assessment

The design is solid and well-structured. The problem statement is clear, the scope is appropriately constrained for v1, and the architecture follows modern Swift conventions. Below are recommended revisions, ordered by impact.

---

## 1. Critical: Add Incremental Sync with Sync Tokens

**Analysis:** The current design polls every 5 minutes with a full event fetch. Google Calendar API supports incremental sync via sync tokens, which returns only changes since the last sync. This is both more efficient and more reliable.

**Rationale:**
- Reduces API quota usage by 90%+ in typical scenarios
- Faster refresh cycles (can poll more frequently without hitting limits)
- Catches deletions and modifications that might be missed between full refreshes
- Google recommends this pattern for production calendar integrations

**Change:**

```diff
 ### Polling Strategy

-- Full refresh every 5 minutes (configurable)
+- Initial full fetch on startup, incremental sync thereafter
+- Sync token stored to request only changes since last fetch
+- Full re-sync if sync token becomes invalid (410 Gone response)
+- Poll every 60 seconds (efficient with incremental sync)
 - On wake from sleep: immediate refresh
 - After dismissing an alert: refresh to catch any changes
+
+### Sync Token Management
+
+```swift
+// Store sync token per calendar
+@AppStorage("syncTokens") var syncTokens: [String: String] = [:]
+```
+
+API call with sync token:
+```
+GET https://www.googleapis.com/calendar/v3/calendars/{calendarId}/events
+  ?syncToken={token}
+```
+
+On 410 response: clear sync token, perform full fetch to resync.
```

---

## 2. Critical: Add Snooze Functionality

**Analysis:** The current design only offers "Join" or "Dismiss" actions. Users frequently need to delay a reminder briefly—they're aware of the meeting but can't join yet.

**Rationale:**
- Standard UX pattern in all reminder systems
- Reduces frustration when alerts fire at inconvenient moments
- Prevents users from dismissing and then forgetting entirely
- Simple to implement with existing timer infrastructure

**Change:**

```diff
 Modal content:

 ┌─────────────────────────────────────┐
 │  Meeting in 10 minutes              │
 │                                     │
 │  Weekly Team Standup                │
 │  10:00 AM - 10:30 AM                │
 │                                     │
-│  [Join Meeting]      [Dismiss]      │
+│  [Join Meeting]  [Snooze ▾]  [Dismiss]│
 └─────────────────────────────────────┘

 Button actions:
 - **Join Meeting:** Opens meeting URL via `NSWorkspace.shared.open(url)`, closes window
+- **Snooze:** Dropdown with options (1 min, 3 min, 5 min). Reschedules alert for selected time.
 - **Dismiss:** Closes window, no further action
+
+Snooze behavior:
+- Snooze replaces remaining scheduled alerts for this event
+- Snoozed alert shows time since original alert ("Snoozed from 10-min warning")
+- Cannot snooze past meeting start time
```

---

## 3. Important: Fix @AppStorage Array Usage

**Analysis:** `@AppStorage` doesn't natively support arrays. The current design shows `@AppStorage("enabledCalendars") var enabledCalendars: [String] = []` which won't compile without additional work.

**Rationale:**
- This is a common Swift gotcha
- Needs explicit JSON encoding/decoding
- Better to address in design than discover during implementation

**Change:**

````diff
 ### Settings Storage

 ```swift
 @Observable
 final class SettingsStore {
     // Alert timing
     @AppStorage("firstAlertMinutes") var firstAlertMinutes: Int = 10
     @AppStorage("secondAlertMinutes") var secondAlertMinutes: Int = 2

     // Sounds
     @AppStorage("firstAlertSound") var firstAlertSound: String = "gentle-chime"
     @AppStorage("secondAlertSound") var secondAlertSound: String = "urgent-tone"
     @AppStorage("customSoundPath") var customSoundPath: String?

-    // Filtering
-    @AppStorage("enabledCalendars") var enabledCalendars: [String] = []
-    @AppStorage("blockedKeywords") var blockedKeywords: [String] = []
+    // Filtering (arrays stored as JSON strings)
+    @AppStorage("enabledCalendarsJSON") private var enabledCalendarsJSON: String = "[]"
+    @AppStorage("blockedKeywordsJSON") private var blockedKeywordsJSON: String = "[]"
+
+    var enabledCalendars: [String] {
+        get { (try? JSONDecoder().decode([String].self, from: Data(enabledCalendarsJSON.utf8))) ?? [] }
+        set { enabledCalendarsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
+    }
+
+    var blockedKeywords: [String] {
+        get { (try? JSONDecoder().decode([String].self, from: Data(blockedKeywordsJSON.utf8))) ?? [] }
+        set { blockedKeywordsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
+    }

     // Polling
     @AppStorage("pollIntervalMinutes") var pollIntervalMinutes: Int = 5
 }
 ```
````

---

## 4. Important: Add Auto-Launch on Login

**Analysis:** For a meeting reminder app, reliability is paramount. If the app doesn't launch at login, users will miss meetings.

**Rationale:**
- Critical for the app's core value proposition
- macOS provides `SMAppService` for this (macOS 13+)
- Should be on by default with ability to disable

**Change:**

````diff
 ### Settings Storage

 ```swift
 @Observable
 final class SettingsStore {
+    // Startup
+    @AppStorage("launchAtLogin") var launchAtLogin: Bool = true
+
     // Alert timing
     @AppStorage("firstAlertMinutes") var firstAlertMinutes: Int = 10
````

````diff
 ### Preferences Window Tabs

 1. **General** - Alert timing (two sliders: 1-30 min each), poll interval
+   - Launch at login toggle (uses SMAppService.mainApp)
 2. **Sounds** - Sound picker for each stage, custom file selector, test button
````

````diff
+### Launch at Login Implementation
+
+```swift
+import ServiceManagement
+
+extension SettingsStore {
+    func updateLaunchAtLogin() {
+        do {
+            if launchAtLogin {
+                try SMAppService.mainApp.register()
+            } else {
+                try SMAppService.mainApp.unregister()
+            }
+        } catch {
+            logger.error("Failed to update launch at login: \(error)")
+        }
+    }
+}
+```
````

---

## 5. Important: Add Event Persistence

**Analysis:** The current design fetches events from the API and holds them in memory only. If the app restarts, all scheduled alerts are lost until the next API fetch.

**Rationale:**
- App crashes or restarts shouldn't cause missed alerts
- Enables faster startup (show cached data immediately)
- Supports better offline handling
- Simple SQLite or JSON file storage is sufficient

**Change:**

```diff
 gcal-notifier/
 ├── Sources/
 │   └── GCalNotifier/
 │       ├── GCalNotifierApp.swift
 │       ├── AppDelegate.swift
 │       ├── Calendar/
 │       │   ├── GoogleCalendarClient.swift
 │       │   ├── CalendarPoller.swift
+│       │   ├── EventCache.swift           # Local persistence layer
 │       │   └── EventModels.swift
```

````diff
 ### Startup Sequence

 1. App launches, `AppDelegate.applicationDidFinishLaunching`
-2. Check for OAuth credentials in Keychain
+2. Load cached events from disk, schedule any pending alerts immediately
+3. Check for OAuth credentials in Keychain
    - Missing → Show "Setup Required" in menu, open Settings on click
    - Present → Initialize `GoogleCalendarClient` with tokens
-3. Create `StatusItemController`, display `📅 --` initially
-4. Start `CalendarPoller`, fetch events immediately
-5. `AlertScheduler` calculates and schedules pending alerts
+4. Create `StatusItemController`, display from cache immediately
+5. Start `CalendarPoller`, fetch events (incremental sync)
+6. `AlertScheduler` reconciles cached alerts with fresh data
+
+### Event Cache
+
+```swift
+actor EventCache {
+    private let fileURL: URL  // ~/Library/Application Support/gcal-notifier/events.json
+
+    func save(_ events: [CalendarEvent]) async throws
+    func load() async throws -> [CalendarEvent]
+    func clear() async throws
+}
+```
+
+Cache invalidation:
+- Clear cache when user signs out
+- Update cache after each successful API sync
+- Cache expires after 24 hours (force full re-sync)
````

---

## 6. Important: Add Global Keyboard Shortcut

**Analysis:** The design mentions KeyboardShortcuts as a dependency but doesn't specify any shortcuts. A "join next meeting" shortcut is highly valuable for power users.

**Rationale:**
- Core efficiency feature for the target user (busy professionals)
- KeyboardShortcuts is already listed as a dependency
- Single most-requested feature in similar apps

**Change:**

````diff
 ### Dependencies

 | Package | Purpose |
 |---------|---------|
-| KeyboardShortcuts (sindresorhus) | Optional global hotkeys |
+| KeyboardShortcuts (sindresorhus) | Global hotkey for "join next meeting" |
 | swift-log (Apple) | Structured logging |
````

````diff
 ### Preferences Window Tabs

 1. **General** - Alert timing (two sliders: 1-30 min each), poll interval
    - Launch at login toggle
+   - Global keyboard shortcut configuration (default: ⌘⇧J)
````

````diff
+### Global Shortcuts
+
+| Shortcut | Action |
+|----------|--------|
+| ⌘⇧J (configurable) | Join the next upcoming meeting with a video link |
+
+Behavior:
+- If next meeting is within 30 minutes: opens meeting URL directly
+- If next meeting is >30 minutes away: shows confirmation ("Join meeting in 2h 15m?")
+- If no upcoming meetings: shows brief notification
````

---

## 7. Recommended: Add Back-to-Back Meeting Awareness

**Analysis:** The current design treats each meeting independently. Users with back-to-back meetings need different alert behavior.

**Rationale:**
- Common scenario in corporate environments
- Firing a 10-minute warning during another meeting is useless
- Opportunity to show "next meeting starts immediately after this one"

**Change:**

````diff
 ### Two-Stage Alerts

 | Stage | Default Timing | Purpose |
 |-------|---------------|---------|
 | First | 10 minutes before | Warning - wrap up what you're doing |
 | Second | 2 minutes before | Urgent - join now |

 Both stages are equally aggressive: modal window + custom sound.
+
+### Back-to-Back Meeting Handling
+
+When meetings are back-to-back (next meeting starts within 5 minutes of previous ending):
+
+1. **First alert suppression:** Skip the 10-minute warning if user is in another meeting
+2. **Transition alert:** Show "Next meeting starting" at the end of current meeting
+3. **Menu bar indicator:** Show `📅 9m → 2m` format (current meeting ends in 9m, next in 2m)
+
+Definition of "in a meeting": current time is between start and end of a meeting with a video link.
````

````diff
 ### Status Item Display

 Format: `[icon] [countdown]`

 | State | Display |
 |-------|---------|
 | Next meeting in 32 minutes | `📅 32m` |
 | Next meeting in 1 hour 15 minutes | `📅 1h 15m` |
+| In meeting, next in 5 minutes | `📅 12m → 5m` |
 | No upcoming meetings with video links | `📅 --` |
 | Within alert window (< 10 min) | Icon pulses/highlights |
````

---

## 8. Recommended: Add All-Day Event Filtering

**Analysis:** The design mentions filtering by video link presence, but doesn't explicitly handle all-day events which should never trigger alerts.

**Rationale:**
- All-day events (holidays, OOO, etc.) should never show alerts
- They technically have a "start time" but it's midnight
- Simple filter that prevents confusing behavior

**Change:**

```diff
 ### Filtering Logic

 Events must pass all filters to trigger alerts:

-1. **Has video link** (automatic) - Event must have extractable meeting URL
-2. **Calendar enabled** (manual) - Event's calendar must be in enabled list
-3. **No blocked keywords** (manual) - Event title must not contain any blocked keywords
+1. **Not all-day event** (automatic) - All-day events never trigger alerts
+2. **Has video link** (automatic) - Event must have extractable meeting URL
+3. **Calendar enabled** (manual) - Event's calendar must be in enabled list
+4. **No blocked keywords** (manual) - Event title must not contain any blocked keywords

 Keyword matching: case-insensitive substring match against event title.
+
+All-day event detection: `event.start.date` is set (date only) vs `event.start.dateTime` (timestamp).
````

---

## 9. Recommended: Add Configurable Alert Stages

**Analysis:** Two stages is a reasonable default, but some users may want three stages (30 min / 10 min / 2 min) or just one.

**Rationale:**
- Different meeting types warrant different preparation times
- Some users prefer more warning, others find multiple alerts annoying
- Simple UI change to make stages configurable

**Change:**

````diff
 ### Settings Storage

 ```swift
 @Observable
 final class SettingsStore {
-    // Alert timing
-    @AppStorage("firstAlertMinutes") var firstAlertMinutes: Int = 10
-    @AppStorage("secondAlertMinutes") var secondAlertMinutes: Int = 2
+    // Alert timing (up to 3 stages, 0 = disabled)
+    @AppStorage("alertStage1Minutes") var alertStage1Minutes: Int = 10
+    @AppStorage("alertStage2Minutes") var alertStage2Minutes: Int = 2
+    @AppStorage("alertStage3Minutes") var alertStage3Minutes: Int = 0  // disabled by default
````

````diff
-### Two-Stage Alerts
+### Configurable Alert Stages

-| Stage | Default Timing | Purpose |
-|-------|---------------|---------|
-| First | 10 minutes before | Warning - wrap up what you're doing |
-| Second | 2 minutes before | Urgent - join now |
+| Stage | Default | Range | Purpose |
+|-------|---------|-------|---------|
+| 1 | 10 min | 1-60 min | Early warning |
+| 2 | 2 min | 1-30 min | Urgent reminder |
+| 3 | Off | 1-60 min | Optional extra early warning |

-Both stages are equally aggressive: modal window + custom sound.
+Each enabled stage fires a modal window + sound. Set to 0 to disable.
+Stages must be in descending order (stage 1 > stage 2 > stage 3).
````

---

## 10. Recommended: Add Explicit Time Zone Handling

**Analysis:** The design doesn't mention time zones, but calendar events can be in different time zones than the user's current location.

**Rationale:**
- Google Calendar API returns times in the event's time zone
- Users traveling will have incorrect alerts without proper handling
- Edge case but important for reliability

**Change:**

````diff
 ### API Usage

 Primary endpoint for fetching events:

 ```
 GET https://www.googleapis.com/calendar/v3/calendars/{calendarId}/events
   ?timeMin={now}
   &timeMax={now + 24h}
   &singleEvents=true
   &orderBy=startTime
+  &timeZone={user's current time zone}
 ```
+
+### Time Zone Handling
+
+- Fetch user's current time zone via `TimeZone.current.identifier`
+- Pass to API to get times in local zone
+- Store events with UTC timestamps internally
+- Display times in user's current zone (handles travel scenarios)
+- Re-fetch events if time zone changes (subscribe to `NSSystemTimeZoneDidChange`)
````

---

## 11. Recommended: Add Menu Bar Update Interval

**Analysis:** The design shows a countdown in the menu bar but doesn't specify how often it updates.

**Rationale:**
- Updating every second is excessive (battery drain)
- Updating every minute creates "jumpy" countdowns
- Should be specified for consistent implementation

**Change:**

````diff
 ### Status Item Display

 Format: `[icon] [countdown]`

 | State | Display |
 |-------|---------|
 | Next meeting in 32 minutes | `📅 32m` |
 | Next meeting in 1 hour 15 minutes | `📅 1h 15m` |
 | No upcoming meetings with video links | `📅 --` |
 | Within alert window (< 10 min) | Icon pulses/highlights |
+
+**Update frequency:**
+- >60 minutes: update every 5 minutes
+- 10-60 minutes: update every minute
+- <10 minutes: update every 15 seconds
+- <2 minutes: update every 5 seconds
+
+Use a single `Timer` that adjusts its interval based on time to next event.
````

---

## 12. Recommended: Add "Join Now" Quick Action in Menu

**Analysis:** Users can click a meeting in the menu to join, but this requires opening the menu and finding the right meeting. A prominent "Join Now" item would be faster.

**Rationale:**
- Reduces friction for the primary user action
- Menu real estate is valuable—use it for the most common action
- Complements but doesn't replace the keyboard shortcut

**Change:**

````diff
 ### Menu Content

 ┌─────────────────────────────────────┐
-│  Next: Weekly Standup         10:00 │
+│  ▶ Join: Weekly Standup    in 8 min │
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

+The "▶ Join:" header item is always visible and clickable.
+- Clicking it opens the next meeting's video link immediately
+- Shows meeting title and countdown
+- Disabled/hidden when no upcoming meetings with video links
````

---

## 13. Minor: Expand Meeting Link Platform Support

**Analysis:** The design mentions extracting links from `conferenceData`, `hangoutLink`, `location`, and `description`. The regex scan should explicitly support more platforms.

**Rationale:**
- Corporate environments use many video platforms
- Missing a link means a missed meeting
- Regex is cheap to expand

**Change:**

````diff
 ### Meeting Link Extraction

 Google Calendar stores video links in multiple places. Extract in priority order:

 1. `conferenceData.entryPoints[].uri` - Structured Meet/Zoom/Teams data
 2. `hangoutLink` - Legacy Google Meet field
 3. `location` field - Sometimes contains Zoom URLs
 4. `description` field - Fallback regex scan for URLs matching known video platforms
+
+**Supported video platforms:**
+- Google Meet (`meet.google.com`)
+- Zoom (`zoom.us`, `*.zoom.us`)
+- Microsoft Teams (`teams.microsoft.com`, `teams.live.com`)
+- Webex (`*.webex.com`)
+- Slack Huddles (`slack.com/huddle`)
+- Around (`around.co`)
+- Tuple (`tuple.app`)
+- Discord (`discord.gg`, `discord.com`)
+- Whereby (`whereby.com`)
+- Loom (live meetings) (`loom.com/meet`)
+
+Regex pattern should match URLs containing these domains.
+Unknown video URLs in `conferenceData` are still used (future-proofs new platforms).
````

---

## 14. Minor: Add Logging Verbosity Control

**Analysis:** The design uses `swift-log` but doesn't specify log levels or how users can adjust verbosity for debugging.

**Rationale:**
- Debugging OAuth issues requires detailed logs
- Normal operation should be quiet
- Users filing bug reports need a way to capture verbose logs

**Change:**

````diff
 ### Dependencies

 | Package | Purpose |
 |---------|---------|
 | KeyboardShortcuts (sindresorhus) | Global hotkey for "join next meeting" |
 | swift-log (Apple) | Structured logging |

+### Logging
+
+Log levels:
+- `debug`: Detailed API responses, timer scheduling, event parsing
+- `info`: OAuth flow steps, successful syncs, alerts fired
+- `warning`: Rate limits, network issues, recoverable errors
+- `error`: Auth failures, critical errors
+
+Default level: `info`
+
+Enable debug logging:
+- Hold Option while clicking "Refresh Now" in menu
+- Or: `defaults write com.yourname.gcal-notifier logLevel debug`
+
+Logs written to `~/Library/Logs/gcal-notifier/` with daily rotation.
````

---

## 15. Minor: Clarify Multiple Simultaneous Alerts

**Analysis:** The design says "Show one modal per meeting, stack them" but doesn't specify the stacking behavior.

**Rationale:**
- Multiple simultaneous alerts need clear UX
- Stacking modals can be overwhelming
- Should specify exact behavior

**Change:**

````diff
 ### Alert Edge Cases

 | Scenario | Handling |
 |----------|----------|
 | Meeting deleted while alert pending | Cancel alert |
 | Meeting time changed | Reschedule alerts on next poll |
 | Meeting starts before alert fires | Skip alerts for events starting within 1 minute |
-| Multiple meetings at same time | Show one modal per meeting, stack them |
+| Multiple meetings at same time | See "Simultaneous Alert Handling" below |
 | User in Do Not Disturb | Alerts still fire (NSPanel ignores DND) |
+
+### Simultaneous Alert Handling
+
+When multiple alerts fire within 30 seconds of each other:
+
+1. Show a combined modal listing all meetings:
+   ```
+   ┌─────────────────────────────────────┐
+   │  2 meetings starting soon           │
+   │                                     │
+   │  ▶ Weekly Standup           10:00   │
+   │  ▶ 1:1 with Sarah           10:00   │
+   │                                     │
+   │  [Join Standup]  [Join 1:1]  [Dismiss All]│
+   └─────────────────────────────────────┘
+   ```
+
+2. Sound plays once, not per meeting
+3. Each meeting has its own join button
+4. "Dismiss All" closes the combined modal
````

---

## Summary of Changes

| Priority | Change | Impact |
|----------|--------|--------|
| Critical | Incremental sync with sync tokens | Performance, reliability |
| Critical | Snooze functionality | Core UX |
| Important | Fix @AppStorage array usage | Correctness |
| Important | Auto-launch on login | Reliability |
| Important | Event persistence | Reliability, startup speed |
| Important | Global keyboard shortcut | Power user efficiency |
| Recommended | Back-to-back meeting awareness | UX for busy users |
| Recommended | All-day event filtering | Correctness |
| Recommended | Configurable alert stages | Flexibility |
| Recommended | Time zone handling | Correctness |
| Recommended | Menu bar update interval | Battery, UX consistency |
| Recommended | "Join Now" quick action in menu | UX efficiency |
| Minor | Expanded platform support | Wider compatibility |
| Minor | Logging verbosity control | Debuggability |
| Minor | Simultaneous alert handling | Edge case UX |

---

## Additional Considerations

### Not Recommended for v1

The following were considered but intentionally excluded:

1. **Push notifications via webhooks** - Requires publicly accessible HTTPS endpoint, complex for desktop app
2. **Per-meeting custom settings** - Adds significant complexity for marginal benefit
3. **Calendar event creation** - Out of scope (read-only is simpler and safer)
4. **Slack status integration** - Scope creep, different problem domain
5. **Analytics/statistics** - Nice-to-have but not core to the value proposition

### Implementation Risk Notes

1. **OAuth token refresh** - Ensure refresh happens proactively (before expiry), not reactively (after 401)
2. **Keychain access** - Test thoroughly with different macOS security settings
3. **NSPanel behavior** - Verify floating panel behavior across Spaces and full-screen apps
4. **SMAppService** - Requires proper entitlements and may need notarization even for personal use
