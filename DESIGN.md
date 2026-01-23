# gcal-notifier Design

macOS menu bar app that provides aggressive, unmissable meeting reminders via Google Calendar API.

## Problem

Google Calendar notifications are easily missed. Slack notification overload makes calendar alerts blend into the noise. Users miss meetings despite having reminders enabled.

## Solution

A dedicated menu bar app that:
- Shows a countdown to your next meeting with a video link
- Fires two-stage modal alerts (10 min warning, 2 min "join now")
- Plays distinctive custom sounds that train your brain to recognize "meeting alert"
- Provides one-click "Join Meeting" from the alert modal
- Filters out non-meetings automatically (no video link = no alert)
- Allows manual filtering via calendar selection and keyword blocklist

## Target Platform

- macOS 14+ (Sonoma)
- Personal use initially (no App Store distribution)
- User provides their own Google Cloud OAuth credentials

## Non-Goals (v1)

- iOS/watchOS companion apps
- Multiple Google account support
- Integration with other calendar providers (Outlook, etc.)
- App Store distribution / built-in OAuth credentials

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
| KeyboardShortcuts (sindresorhus) | Optional global hotkeys |
| swift-log (Apple) | Structured logging |

No Sparkle needed initially (personal use, manual updates).

### Project Structure

```
gcal-notifier/
├── Sources/
│   └── GCalNotifier/
│       ├── GCalNotifierApp.swift      # @main entry, SwiftUI App
│       ├── AppDelegate.swift          # NSApplicationDelegate, status item setup
│       ├── Calendar/
│       │   ├── GoogleCalendarClient.swift   # API client, OAuth token management
│       │   ├── CalendarPoller.swift         # Periodic fetch, event diffing
│       │   └── EventModels.swift            # Event, MeetingLink types
│       ├── Alerts/
│       │   ├── AlertScheduler.swift         # Schedules alerts based on events
│       │   ├── AlertWindowController.swift  # Modal window management
│       │   └── SoundPlayer.swift            # AVFoundation audio playback
│       ├── MenuBar/
│       │   ├── StatusItemController.swift   # NSStatusItem management
│       │   └── MenuContentView.swift        # SwiftUI menu content
│       ├── Settings/
│       │   ├── SettingsStore.swift          # @Observable preferences
│       │   ├── PreferencesView.swift        # SwiftUI settings window
│       │   └── OAuthSetupView.swift         # Credential configuration
│       └── Resources/
│           └── Sounds/                      # Built-in alert sounds
├── Package.swift
└── README.md
```

### App Configuration

- `LSUIElement = true` in Info.plist (no Dock icon)
- Menu bar only presence

---

## Google Calendar Integration

### Authentication Flow

1. User creates a Google Cloud project and enables Calendar API
2. User creates OAuth 2.0 credentials (Desktop app type)
3. User pastes Client ID and Client Secret into gcal-notifier Settings
4. App opens browser for Google sign-in, receives authorization code via localhost redirect
5. App exchanges code for access + refresh tokens, stores in macOS Keychain
6. Tokens auto-refresh; user only re-authenticates if refresh token is revoked

### API Usage

Primary endpoint for fetching events:

```
GET https://www.googleapis.com/calendar/v3/calendars/{calendarId}/events
  ?timeMin={now}
  &timeMax={now + 24h}
  &singleEvents=true
  &orderBy=startTime
```

Calendar list endpoint (for settings):

```
GET https://www.googleapis.com/calendar/v3/users/me/calendarList
```

### Polling Strategy

- Full refresh every 5 minutes (configurable)
- On wake from sleep: immediate refresh
- After dismissing an alert: refresh to catch any changes

### Meeting Link Extraction

Google Calendar stores video links in multiple places. Extract in priority order:

1. `conferenceData.entryPoints[].uri` - Structured Meet/Zoom/Teams data
2. `hangoutLink` - Legacy Google Meet field
3. `location` field - Sometimes contains Zoom URLs
4. `description` field - Fallback regex scan for URLs matching known video platforms

---

## Alert System

### Two-Stage Alerts

| Stage | Default Timing | Purpose |
|-------|---------------|---------|
| First | 10 minutes before | Warning - wrap up what you're doing |
| Second | 2 minutes before | Urgent - join now |

Both stages are equally aggressive: modal window + custom sound.

### Modal Window

A floating `NSPanel` with properties:
- `level: .floating` - Appears above all other windows
- `styleMask: [.titled, .closable]` - Standard window chrome
- `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]` - Visible on all desktops

Modal content:

```
┌─────────────────────────────────────┐
│  Meeting in 10 minutes              │
│                                     │
│  Weekly Team Standup                │
│  10:00 AM - 10:30 AM                │
│                                     │
│  [Join Meeting]      [Dismiss]      │
└─────────────────────────────────────┘
```

Button actions:
- **Join Meeting:** Opens meeting URL via `NSWorkspace.shared.open(url)`, closes window
- **Dismiss:** Closes window, no further action

### Sound Playback

`SoundPlayer` uses AVFoundation:
- Load sound from bundle (built-in) or user-specified file path
- Play on alert fire, before showing modal
- Respect system volume

Sound options:
- 2-3 built-in distinctive sounds (not standard macOS sounds)
- Custom sound file support (.mp3, .wav, .aiff)
- Separate sound selection for each alert stage

---

## Menu Bar UI

### Status Item Display

Format: `[icon] [countdown]`

| State | Display |
|-------|---------|
| Next meeting in 32 minutes | `📅 32m` |
| Next meeting in 1 hour 15 minutes | `📅 1h 15m` |
| No upcoming meetings with video links | `📅 --` |
| Within alert window (< 10 min) | Icon pulses/highlights |

### Menu Content

```
┌─────────────────────────────────────┐
│  Next: Weekly Standup         10:00 │
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

---

## Filtering & Configuration

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

    // Filtering
    @AppStorage("enabledCalendars") var enabledCalendars: [String] = []
    @AppStorage("blockedKeywords") var blockedKeywords: [String] = []

    // Polling
    @AppStorage("pollIntervalMinutes") var pollIntervalMinutes: Int = 5
}
```

### Preferences Window Tabs

1. **General** - Alert timing (two sliders: 1-30 min each), poll interval
2. **Sounds** - Sound picker for each stage, custom file selector, test button
3. **Calendars** - Checklist of calendars from Google account, toggle each
4. **Keywords** - Text field to add blocked keywords, list to remove them
5. **Account** - OAuth credentials input, sign-in status, sign-out button

### Filtering Logic

Events must pass all filters to trigger alerts:

1. **Has video link** (automatic) - Event must have extractable meeting URL
2. **Calendar enabled** (manual) - Event's calendar must be in enabled list
3. **No blocked keywords** (manual) - Event title must not contain any blocked keywords

Keyword matching: case-insensitive substring match against event title.

---

## Data Flow

### Startup Sequence

1. App launches, `AppDelegate.applicationDidFinishLaunching`
2. Check for OAuth credentials in Keychain
   - Missing → Show "Setup Required" in menu, open Settings on click
   - Present → Initialize `GoogleCalendarClient` with tokens
3. Create `StatusItemController`, display `📅 --` initially
4. Start `CalendarPoller`, fetch events immediately
5. `AlertScheduler` calculates and schedules pending alerts

### Event Refresh Cycle

```
CalendarPoller (every 5 min)
    │
    ▼
GoogleCalendarClient.fetchEvents()
    │
    ▼
Filter: has video link?
    │
    ▼
Filter: calendar enabled?
    │
    ▼
Filter: keyword blocklist?
    │
    ▼
Filtered events → AlertScheduler.reschedule()
                → StatusItemController.updateDisplay()
```

### Alert Trigger Flow

```
Timer fires (10 min before meeting)
    │
    ▼
SoundPlayer.play(firstAlertSound)
    │
    ▼
AlertWindowController.show(event, stage: .first)
    │
    ▼
User clicks [Join] ─────► NSWorkspace.open(meetingURL)
    or [Dismiss]                    │
         │                          ▼
         ▼                   Window closes
   Window closes
```

---

## Error Handling

### OAuth Errors

| Error | Handling |
|-------|----------|
| Token refresh fails | Show "Re-authenticate" badge on menu bar icon, prompt in Settings |
| Invalid credentials | Clear tokens, return to setup state |
| Network offline | Use cached events, show "Offline" indicator, retry on connectivity change |

### Calendar API Errors

| Error | Handling |
|-------|----------|
| Rate limited (403) | Back off exponentially, show warning in menu |
| Calendar not found | Remove from enabled list, notify user |
| Partial failure | Show events that succeeded, log failures |

### Alert Edge Cases

| Scenario | Handling |
|----------|----------|
| Meeting deleted while alert pending | Cancel alert |
| Meeting time changed | Reschedule alerts on next poll |
| Meeting starts before alert fires | Skip alerts for events starting within 1 minute |
| Multiple meetings at same time | Show one modal per meeting, stack them |
| User in Do Not Disturb | Alerts still fire (NSPanel ignores DND) |

### Wake from Sleep

- Subscribe to `NSWorkspace.didWakeNotification`
- Immediate calendar refresh
- Check if any alerts were missed while sleeping
- If meeting started < 5 min ago, show "Meeting started!" alert

---

## First Launch Experience

1. Menu shows "Setup Required - Click to configure"
2. Settings opens to Account tab
3. Inline instructions:
   - Create Google Cloud project
   - Enable Calendar API
   - Create OAuth credentials (Desktop app)
   - Paste Client ID and Secret
4. Link to documentation with screenshots
5. "Sign In" button initiates OAuth flow

---

## Implementation Order

| Phase | Components | Description |
|-------|------------|-------------|
| 1 | Project scaffold | Package.swift, app entry point, status item skeleton |
| 2 | Settings infrastructure | SettingsStore, basic preferences window |
| 3 | OAuth flow | Credential input, token exchange, Keychain storage |
| 4 | Calendar fetching | API client, event parsing, meeting link extraction |
| 5 | Menu bar UI | Countdown display, meeting list menu |
| 6 | Alert system | Scheduler, modal window, sound playback |
| 7 | Filtering | Calendar selection, keyword blocklist |
| 8 | Polish | Error handling, wake-from-sleep, edge cases |

---

## Reference Implementation

CodexBar (`../CodexBar`) provides patterns for:
- Swift Package Manager macOS menu bar app structure
- `NSStatusItem` with SwiftUI content
- Keychain credential storage
- Preferences window with tabs
- Logging infrastructure
- No-Dock-icon configuration
