# Alert Delivery Reliability Smoke Test

**Purpose:** Validate real macOS behavior for the dual-path alert system after the OS-backed delivery migration.

Unit tests cover alert state transitions, scheduling contracts, and stale-trigger guards. This smoke test covers the
user-visible behavior that requires macOS notification delivery, app lifecycle boundaries, sleep/wake, and Login Items.

Do not close GitHub issue `#14` until the completed result matrix is posted there. File separate defects for every
failed row before closing the smoke-test issue.

## Prerequisites

- macOS 15 or later.
- A test Google Calendar that can create short-lived events with Google Meet links.
- GCal Notifier authenticated against that calendar.
- A build installed or launched with `make start`.
- Stage 1 set to 10 minutes before start.
- Stage 2 set to 2 minutes before start.
- Notification settings for GCal Notifier can be changed during the run.
- Launch at Login can be changed during the run.

Start a log capture before running the matrix:

```bash
log stream --style compact --predicate 'subsystem == "com.gcal-notifier"'
```

For each alert row, record the event title, event start time, observed alert time, visible surface, action taken, and any
`alert_diagnostic` lines that mention the alert id.

## Setup

1. Run `make start`.
2. Open Settings.
3. Confirm the Account tab is signed in.
4. Confirm the test calendar is enabled.
5. In General, set Stage 1 to `10 minutes` and Stage 2 to `2 minutes`.
6. In macOS System Settings > Notifications > GCal Notifier, allow notifications and enable sounds.
7. In macOS System Settings > General > Login Items, allow GCal Notifier if prompted.
8. Click the menu bar icon and run `Refresh Now`.

## Result Matrix

Record one of `PASS`, `FAIL`, or `SKIP` for every row. `SKIP` must include a reason.

### M1: Fresh Stage 1 Modal Delivery

- Area: Modal
- Steps: Create an event 12 minutes out. Keep the app running and awake. Wait for Stage 1.
- Expected: A fresh Stage 1 modal appears near T-10. OS notification may also be present.
- Expected: Showing the modal does not acknowledge the alert.
- Result:
- Notes / Defect:

### M2: Fresh Stage 2 Modal Delivery

- Area: Modal
- Steps: Create an event 4 minutes out. Keep the app running and awake. Wait for Stage 2.
- Expected: A fresh Stage 2 modal appears near T-2 with urgent sound and enabled actions.
- Result:
- Notes / Defect:

### O1: Stage 1 OS Fallback While App Is Not Running

- Area: OS fallback
- Steps: Create an event 12 minutes out. Sync. Quit the app before T-10. Wait for Stage 1.
- Expected: macOS shows a Stage 1 notification with event title, context, and actions.
- Expected: No app process is required at fire time.
- Result:
- Notes / Defect:

### O2: Stage 2 OS Fallback While App Is Not Running

- Area: OS fallback
- Steps: Create an event 4 minutes out. Sync. Quit the app before T-2. Wait for Stage 2.
- Expected: macOS shows a Stage 2 time-sensitive notification with sound, title, context, and actions.
- Result:
- Notes / Defect:

### L1: App Backgrounded

- Area: Lifecycle
- Steps: Create an event 4 minutes out. Sync. Put another app in front.
- Expected: Alert remains user-visible through the modal path, OS path, or both. There is no silent miss.
- Result:
- Notes / Defect:

### L2: Relaunch Before Alert Boundary

- Area: Lifecycle
- Steps: Create an event 6 minutes out. Sync. Quit and relaunch before T-2.
- Expected: Relaunch reconciliation restores future alert effects. Stage 2 appears on time.
- Result:
- Notes / Defect:

### L3: Relaunch After Alert Boundary

- Area: Lifecycle
- Steps: Create an event 4 minutes out. Sync. Quit before T-2.
- Steps: Relaunch after the event has started.
- Expected: No stale modal appears on relaunch.
- Expected: Delivered OS notification remains visible until user action or invalidation.
- Result:
- Notes / Defect:

### W1: Sleep/Wake Near Alert Boundary

- Area: Lifecycle
- Steps: Create an event 6 minutes out. Sync. Sleep the Mac before T-2.
- Steps: Wake shortly after T-2.
- Expected: Wake triggers sync/reconciliation. No stale modal appears.
- Expected: Delivered OS notification remains visible if macOS delivered it.
- Result:
- Notes / Defect:

### W2: Stale Wake Guard

- Area: Lifecycle
- Steps: Create an event 5 minutes out. Sync. Sleep through the meeting start.
- Steps: Wake more than 5 minutes after start.
- Expected: No late modal appears after wake.
- Expected: Diagnostics show stale local trigger no-op if a local trigger fires.
- Result:
- Notes / Defect:

### G1: Launch At Login Healthy Path

- Area: Login
- Steps: Enable Launch at Login. Reboot or log out/in.
- Expected: GCal Notifier starts automatically.
- Expected: Modal availability is not degraded in the menu.
- Result:
- Notes / Defect:

### G2: Launch At Login Disabled Degraded State

- Area: Login
- Steps: Disable Launch at Login. Open the menu.
- Expected: Menu or settings surface degraded modal availability after login/reboot.
- Expected: The degraded state offers a path to Login Items settings.
- Result:
- Notes / Defect:

### G3: Launch At Login Approval-Required Degraded State

- Area: Login
- Steps: Put Login Items into an approval-required state if macOS exposes it. Open the menu.
- Expected: Menu or settings surfaces approval-required state.
- Expected: The degraded state offers a path to Login Items settings.
- Result:
- Notes / Defect:

### P1: Notification Permission Denied Degraded State

- Area: Permissions
- Steps: Deny GCal Notifier notifications in System Settings. Open the menu.
- Expected: Menu surfaces degraded durable OS delivery.
- Expected: The degraded state offers a path to notification settings.
- Result:
- Notes / Defect:

### P2: Notification Permission Restored Healthy State

- Area: Permissions
- Steps: Restore notification permission. Open the menu.
- Expected: Durable-delivery warning disappears.
- Expected: Future OS fallback notifications can be delivered.
- Result:
- Notes / Defect:

### A1: Join From Modal

- Area: Modal actions
- Steps: Trigger a fresh modal on an event with a Meet link. Click Join.
- Expected: Meeting URL opens and only the current alert stage is acknowledged.
- Result:
- Notes / Defect:

### A2: Dismiss From Modal

- Area: Modal actions
- Steps: Trigger a fresh modal. Click Dismiss.
- Expected: Current alert stage is acknowledged.
- Expected: Other stages are not suppressed unless they are separately resolved.
- Result:
- Notes / Defect:

### A3: Snooze From Modal

- Area: Modal actions
- Steps: Trigger a fresh modal before the meeting. Click Snooze 1m.
- Expected: Current alert is rescheduled to the snooze time.
- Expected: Snooze options that would cross Stage 2 or meeting start are unavailable.
- Result:
- Notes / Defect:

### A4: Join From OS Notification

- Area: OS actions
- Steps: Trigger an OS fallback notification. Click Join.
- Expected: App opens if needed, meeting URL opens, and only the current alert stage is acknowledged.
- Result:
- Notes / Defect:

### A5: Dismiss From OS Notification

- Area: OS actions
- Steps: Trigger an OS fallback notification. Click Dismiss.
- Expected: Current alert stage is acknowledged.
- Expected: Pending and delivered effects for that alert are cleared.
- Result:
- Notes / Defect:

### A6: Snooze From OS Notification

- Area: OS actions
- Steps: Trigger an OS fallback notification. Click Snooze 1m or 3m.
- Expected: Current alert request and local modal trigger are replaced with the snoozed fire time.
- Result:
- Notes / Defect:

## Required Evidence

Attach or paste the following into GitHub issue `#14` before closing it:

- macOS version.
- App build or commit SHA.
- Whether the app was run with `make start`, a packaged debug app, or a release app.
- Notification settings state at start and after degraded-state tests.
- Launch-at-login state at start and after degraded-state tests.
- Completed result matrix.
- Relevant `alert_diagnostic` log lines for any failure.
- Links to follow-up defect issues for every failed row.

## Issue Comment Template

```markdown
## Manual macOS reliability smoke test results

- Date:
- Tester:
- macOS:
- App commit:
- Build source:
- Notification settings:
- Launch-at-login status:

| ID | Result | Notes / Defect |
| --- | --- | --- |
| M1 |  |  |
| M2 |  |  |
| O1 |  |  |
| O2 |  |  |
| L1 |  |  |
| L2 |  |  |
| L3 |  |  |
| W1 |  |  |
| W2 |  |  |
| G1 |  |  |
| G2 |  |  |
| G3 |  |  |
| P1 |  |  |
| P2 |  |  |
| A1 |  |  |
| A2 |  |  |
| A3 |  |  |
| A4 |  |  |
| A5 |  |  |
| A6 |  |  |

Follow-up defects:

- None, or links to filed issues.
```
