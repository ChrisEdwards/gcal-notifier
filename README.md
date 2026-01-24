# GCal Notifier

A macOS menu bar app that delivers **unmissable** Google Calendar meeting reminders. No more missing meetings because notifications blend into Slack noise.

## The Problem

Google Calendar's built-in notifications are easily missed:
- They look identical to hundreds of daily Slack messages
- They disappear silently if you're focused on work
- They don't scale urgency as meeting time approaches
- They fail silently when offline

## The Solution

GCal Notifier provides aggressive, two-stage alerts with custom sounds, modal windows, and smart context awareness:

```
📅 32m → Meeting countdown in menu bar
🔔 10 min  → Stage 1: Gentle heads-up notification
⚠️  2 min  → Stage 2: Modal window + urgent sound (demands attention)
```

## Features

### Core
- **Adaptive Menu Bar** — Live countdown to your next meeting
- **Two-Stage Alerts** — Early warning + urgent reminder with configurable timing
- **Custom Sounds** — Different sounds per stage, or use your own audio files
- **Meeting Link Detection** — Extracts Join URLs from Meet, Zoom, Teams, Webex, Slack Huddles
- **One-Click Join** — Open video call directly from alert modal
- **Global Keyboard Shortcuts** — `⌘⇧J` to join next meeting instantly

### Smart Filtering
- **Calendar Selection** — Enable/disable specific calendars
- **Keyword Blocking** — Skip alerts for events matching keywords (e.g., "OOO", "Block")
- **Force-Alert Keywords** — Always alert for critical events (e.g., "Interview")
- **All-Day Event Exclusion** — No alerts for holidays or day-long blocks

### Context Awareness
- **Screen Share Detection** — Suppresses modals during screen sharing
- **Do Not Disturb Respect** — Optional sound suppression during Focus modes
- **Back-to-Back Handling** — Intelligent alert downgrading for consecutive meetings
- **Conflict Detection** — Warns about overlapping meetings
- **Sleep/Wake Recovery** — Reschedules alerts after laptop wake

### Reliability
- **Offline Resilience** — Cached events keep alerts working without network
- **Proactive Token Refresh** — OAuth tokens refresh before expiration
- **Adaptive Sync** — Polls more frequently as meetings approach
- **Launch at Login** — Start automatically with macOS

## Requirements

- macOS 15.0+ (Sequoia)
- Google Account with Calendar access
- Google Cloud OAuth credentials (free, see setup below)

## Installation

### Download Release
Download the latest `.app` from [Releases](https://github.com/ChrisEdwards/gcal-notifier/releases) and drag to Applications.

### Build from Source
```bash
git clone https://github.com/ChrisEdwards/gcal-notifier.git
cd gcal-notifier
make package RELEASE=1
# App bundle created in .build/
```

## Setup

### 1. Create Google Cloud Credentials

GCal Notifier requires your own OAuth credentials (free tier is sufficient):

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or select existing)
3. Enable the **Google Calendar API**:
   - Navigate to *APIs & Services* → *Library*
   - Search "Google Calendar API" → Enable
4. Create OAuth credentials:
   - Go to *APIs & Services* → *Credentials*
   - Click *Create Credentials* → *OAuth client ID*
   - Application type: **Desktop app**
   - Name: "GCal Notifier" (or anything)
5. Copy the **Client ID** and **Client Secret**

### 2. Configure the App

1. Launch GCal Notifier — it appears in your menu bar as 📅
2. Click the icon → *Settings* → *Account* tab
3. Paste your Client ID and Client Secret
4. Click *Sign In* — browser opens for Google authorization
5. Grant read-only calendar access
6. Select which calendars to monitor in *Calendars* tab

### 3. Customize Alerts (Optional)

In *Settings* → *Alerts* tab:
- **Stage 1 timing** — Minutes before meeting for first alert (default: 10)
- **Stage 2 timing** — Minutes before for urgent modal (default: 2)
- **Sounds** — Choose from built-in sounds or add custom audio files
- **Snooze duration** — How long snooze delays the alert

## Usage

### Menu Bar
- **Click icon** — Shows upcoming meetings and quick actions
- **Right-click** — Access settings and sign out

### Alert Modal
When an urgent alert fires:
- **Join** — Opens meeting link in default browser
- **Snooze** — Delays alert by configured duration
- **Open in Calendar** — Opens event in Google Calendar web
- **Dismiss** — Closes alert without action

### Keyboard Shortcuts
- `⌘⇧J` — Join next meeting immediately (configurable in Settings)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     GCalNotifier (App)                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │  Menu Bar    │  │ Alert Window │  │   Settings UI    │   │
│  │  Controller  │  │  Controller  │  │   (SwiftUI)      │   │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘   │
└─────────┼─────────────────┼────────────────────┼────────────┘
          │                 │                    │
┌─────────┼─────────────────┼────────────────────┼────────────┐
│         ▼                 ▼                    ▼             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                  GCalNotifierCore                     │   │
│  │  ┌────────────┐  ┌─────────────┐  ┌───────────────┐  │   │
│  │  │ SyncEngine │  │ AlertEngine │  │ SettingsStore │  │   │
│  │  │ (adaptive) │  │   (actor)   │  │ (@Observable) │  │   │
│  │  └─────┬──────┘  └──────┬──────┘  └───────────────┘  │   │
│  │        │                │                             │   │
│  │        ▼                ▼                             │   │
│  │  ┌────────────┐  ┌─────────────┐  ┌───────────────┐  │   │
│  │  │  Calendar  │  │Notification │  │   EventCache  │  │   │
│  │  │   Client   │  │  Scheduler  │  │   (offline)   │  │   │
│  │  └─────┬──────┘  └─────────────┘  └───────────────┘  │   │
│  │        │                                              │   │
│  │        ▼                                              │   │
│  │  ┌────────────┐  ┌─────────────┐                     │   │
│  │  │   OAuth    │  │  Keychain   │                     │   │
│  │  │  Provider  │◀─│   Manager   │                     │   │
│  │  └────────────┘  └─────────────┘                     │   │
│  └──────────────────────────────────────────────────────┘   │
│                   GCalNotifierCore (Testable)                │
└─────────────────────────────────────────────────────────────┘
```

**Two-Target Design:**
- **GCalNotifierCore** — Business logic, testable without UI dependencies
- **GCalNotifier** — SwiftUI app with system integration

## Development

### Prerequisites
- Xcode 16+ (Swift 6)
- macOS 15.0+

### Build Commands
```bash
make build          # Debug build
make build-release  # Optimized release build
make start          # Build and run
make stop           # Kill running instance
```

### Testing
```bash
make test           # Run all tests
make test-parallel  # Parallel test execution
make check          # Lint + static analysis
make check-test     # Both checks and tests
```

### Code Quality
```bash
make format         # Auto-format code
make lint           # Run SwiftLint
make all            # Format, lint, test
```

### Project Structure
```
Sources/
├── GCalNotifierCore/     # Testable business logic
│   ├── Auth/             # OAuth 2.0 implementation
│   ├── Calendar/         # API client, sync, filtering
│   ├── Alerts/           # Alert scheduling engine
│   ├── Settings/         # Preferences storage
│   └── Data/             # Caching and persistence
│
└── GCalNotifier/         # macOS app
    ├── System/           # AppDelegate, lifecycle
    ├── MenuBar/          # Status item UI
    ├── Alerts/           # Modal windows, sounds
    ├── Settings/         # Settings UI (SwiftUI)
    └── Shortcuts/        # Global hotkeys
```

## Privacy & Security

- **Read-Only Access** — Only requests `calendar.readonly` OAuth scope
- **Local Credentials** — OAuth tokens stored in macOS Keychain, never on disk
- **No Telemetry** — Zero analytics, tracking, or network calls except Google Calendar API
- **App Sandbox** — Runs with minimal entitlements (network + keychain only)
- **Your Credentials** — You control the OAuth app; revoke access anytime in Google settings

## Troubleshooting

### "Calendar sync failed"
- Check internet connection
- Verify OAuth credentials in Settings → Account
- Try signing out and back in

### Alerts not firing
- Ensure notifications are enabled in System Settings → Notifications
- Check that the calendar is enabled in Settings → Calendars
- Verify the event isn't matching a blocked keyword

### No meeting link detected
- GCal Notifier checks: Google Meet data, hangoutLink, location field, description
- Some calendar apps store links in non-standard fields
- Manually add the link to the event description as a workaround

### App not starting at login
- Enable in Settings → General → "Launch at Login"
- Check System Settings → General → Login Items

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Run `make all` before committing (format, lint, test)
4. Submit a pull request

### Code Standards
- Swift 6 strict concurrency
- Max 150 character lines
- Max 20 cyclomatic complexity per function
- Max 100 lines per function body

## License

MIT License

## Acknowledgments

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus
- [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) by Steffan Andrews
