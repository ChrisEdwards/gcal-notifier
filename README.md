# GCal Notifier

A macOS menu bar app that delivers **unmissable** Google Calendar meeting reminders. No more missing meetings because notifications blend into Slack noise.

## Why GCal Notifier?

Google Calendar's built-in notifications are easily missed:
- They look identical to hundreds of daily Slack messages
- They disappear silently if you're focused on work
- They don't scale urgency as meeting time approaches
- They fail silently when offline

**GCal Notifier fixes all of this** with aggressive, two-stage alerts that demand your attention when it matters.

## How It Works

```
Menu Bar:     📅 32m     ← Live countdown to your next meeting

10 min before:  🔔 Gentle notification appears
                   "Team Standup in 10 minutes"

 2 min before:  ⚠️ Modal window + urgent sound
                   Can't miss it — requires action to dismiss
```

## Quick Start

1. **Download** from [Releases](https://github.com/ChrisEdwards/gcal-notifier/releases)
2. **Create OAuth credentials** at [Google Cloud Console](https://console.cloud.google.com/) (free)
3. **Launch the app** — click 📅 in menu bar → Settings
4. **Paste credentials** and sign in with Google
5. **Done!** You'll never miss a meeting again

## Features

### Menu Bar
- **Live Countdown** — Shows time until your next meeting (e.g., "32m", "2h 15m")
- **Today's Meetings** — Click to see your full schedule at a glance
- **Visual Indicators**:
  - 📹 Meeting has video link (click to see Join option)
  - 📅 Meeting without video link
  - ⚠️ Conflicting meetings at same time
- **Quick Actions** — Join, copy link, or open in Google Calendar

### Two-Stage Alerts

| Stage | Default | What Happens |
|-------|---------|--------------|
| **Stage 1** | 10 min before | Notification banner + sound |
| **Stage 2** | 2 min before | Modal window + urgent sound (can't ignore!) |

Both timing and sounds are fully customizable.

### Alert Window
When the urgent alert fires, you get:
- **Join** — One click to open video call (Return key)
- **Snooze** — Push back 1, 3, or 5 minutes
- **Open in Calendar** — View full event details
- **Dismiss** — Close and acknowledge (Escape key)

### Smart Features
- **Snooze with Memory** — Snoozed alerts show "Snoozed 2 time(s)" so you know
- **Automatic Sync** — Polls more frequently as meetings approach (1min/5min/15min)
- **Offline Mode** — Cached events keep alerts working without internet
- **Sleep Recovery** — Reschedules alerts after your Mac wakes up

### Meeting Link Detection
Automatically extracts join URLs from:
- Google Meet
- Zoom
- Microsoft Teams
- Webex
- Slack Huddles
- Any URL in the event description

### Smart Filtering
- **Calendar Selection** — Choose which calendars to monitor
- **Keyword Blocking** — Skip alerts for events containing "OOO", "Block", etc.
- **Force-Alert Keywords** — Always alert for "Interview", "Important", etc.
- **All-Day Events** — Automatically excluded (no alerts for holidays)

### Context Awareness
- **Screen Share Detection** — Suppresses modal popups during presentations
- **Do Not Disturb** — Optional sound suppression during Focus modes
- **Back-to-Back Meetings** — Intelligent alert handling for consecutive events
- **Conflict Warnings** — Alerts you about overlapping meetings

### Keyboard Shortcuts
- **⌘⇧J** — Join next meeting instantly (customizable)
- **Return** — Join from alert window
- **Escape** — Dismiss alert window

## Installation

### Option 1: Download Release
Download the latest `.app` from [Releases](https://github.com/ChrisEdwards/gcal-notifier/releases) and drag to Applications.

### Option 2: Build from Source
```bash
git clone https://github.com/ChrisEdwards/gcal-notifier.git
cd gcal-notifier
make package RELEASE=1
# App bundle created in .build/
```

## Setup Guide

### Step 1: Create Google Cloud Credentials (5 minutes)

GCal Notifier needs OAuth credentials to access your calendar. This is free and gives you full control.

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or use existing)
3. **Enable the Google Calendar API**:
   - Go to *APIs & Services* → *Library*
   - Search "Google Calendar API"
   - Click **Enable**
4. **Create OAuth credentials**:
   - Go to *APIs & Services* → *Credentials*
   - Click *Create Credentials* → *OAuth client ID*
   - If prompted, configure the OAuth consent screen first:
     - User Type: External
     - App name: "GCal Notifier"
     - Add your email as a test user
   - Application type: **Desktop app**
   - Name: "GCal Notifier"
5. **Copy** the Client ID and Client Secret

### Step 2: Configure the App

1. Launch GCal Notifier — look for 📅 in your menu bar
2. Click the icon → **Settings**
3. In the **Account** tab:
   - Paste your Client ID
   - Paste your Client Secret
   - Click **Sign In**
4. Browser opens — sign in with Google and grant calendar access
5. In the **Calendars** tab, select which calendars to monitor

### Step 3: Customize (Optional)

**Alerts Tab:**
- Adjust Stage 1 and Stage 2 timing
- Choose different sounds for each stage
- Add a custom sound file if you want

**Filters Tab:**
- Add keywords to block (events won't trigger alerts)
- Add force-alert keywords (always trigger alerts)

**General Tab:**
- Enable "Launch at Login" for automatic startup

## Privacy & Security

- **Read-Only** — Only requests `calendar.readonly` permission
- **Secure Storage** — OAuth tokens stored in macOS Keychain
- **No Tracking** — Zero analytics or telemetry
- **Your Credentials** — You control the OAuth app; revoke anytime in Google settings
- **Sandboxed** — Minimal app permissions (network + keychain only)

## Troubleshooting

### Alerts not firing
1. **Check notification permissions**: System Settings → Notifications → GCal Notifier
2. **Verify calendar is enabled**: Settings → Calendars tab
3. **Check blocked keywords**: Settings → Filters tab
4. **Force sync**: Click menu bar icon → Refresh Now

### "Calendar sync failed"
1. Check your internet connection
2. Try signing out and back in (Settings → Account)
3. Verify your OAuth credentials are correct

### Menu bar shows "--" instead of countdown
1. No upcoming meetings with video links today
2. Try clicking Refresh Now in the menu
3. Check that you have calendars selected in Settings

### No meeting link detected for an event
GCal Notifier checks these locations:
- Google Meet conference data
- Event location field
- Event description (any URL)

**Workaround**: Add the meeting URL directly to the event description.

### App not starting at login
1. Enable: Settings → General → Launch at Login
2. Check: System Settings → General → Login Items

### Keychain password prompts (developers)
If building from source and getting repeated Keychain prompts:
```bash
./Scripts/setup_dev_certificate.sh
```
This creates a self-signed certificate that persists across rebuilds.

## Development

### Prerequisites
- Xcode 16+ (Swift 6)
- macOS 15.0+

### Build Commands
```bash
make build          # Debug build
make start          # Build and run
make stop           # Kill running instance
make build-release  # Optimized release build
make package        # Create .app bundle
```

### Testing
```bash
make test           # Run all tests
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
│   ├── Auth/             # OAuth 2.0 + Keychain
│   ├── Calendar/         # API client, sync, filtering
│   ├── Alerts/           # Alert scheduling engine
│   ├── Settings/         # Preferences storage
│   └── Data/             # Caching and persistence
│
└── GCalNotifier/         # macOS app
    ├── MenuBar/          # Status item + dropdown menu
    ├── Alerts/           # Modal windows, sounds
    ├── Settings/         # Settings UI (SwiftUI)
    └── Shortcuts/        # Global hotkeys
```

### Architecture

**Two-Target Design:**
- **GCalNotifierCore** — Business logic, fully testable without UI
- **GCalNotifier** — SwiftUI app with system integration

Key components:
- `SyncEngine` — Adaptive polling (1/5/15 min based on next meeting)
- `AlertEngine` — Schedules and fires alerts with suppression logic
- `EventCache` — Offline-capable event storage
- `KeychainManager` — Secure credential storage

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Run `make all` before committing
4. Submit a pull request

### Code Standards
- Swift 6 strict concurrency
- Max 150 character lines
- Max 20 cyclomatic complexity
- Max 100 lines per function

## License

MIT License

## Acknowledgments

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus
- [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) by Steffan Andrews
