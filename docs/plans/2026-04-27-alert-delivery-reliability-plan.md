# Alert Delivery Reliability Plan

**Date:** 2026-04-27

**Goal:** Make meeting alerts reliable enough to trust by moving durable alert delivery to macOS while preserving the
custom modal as a first-class running-app experience whenever the app is awake, running, and the alert is fresh.

## Summary

The current alert pipeline is optimized for custom UI, not for reliable delivery. The app schedules production alerts
with in-process `DispatchSourceTimer` instances via `DispatchAlertScheduler`, then tries to recover around sleep,
wake, relaunch, and cache drift using heuristics.

That tradeoff is the root cause of the current inconsistency:

- alerts can be missed if the app is not runnable at the exact fire time
- alerts can be dropped on startup before `AlertEngine` is ready
- relaunch recovery ignores alerts whose scheduled time has already passed
- wake recovery uses a narrow grace window and can race stale timers
- final delivery depends on `EventCache` still containing the event at fire time

The correct long-term model is:

- macOS notifications are the durable source of truth for alert delivery
- the custom modal remains the preferred hard-to-miss experience while the app is running
- local modal triggers are useful, but they are not the only delivery path
- if the modal cannot be shown, the user still receives an OS-level alert

## Motivation

This app exists to solve a reliability problem. A reminder that fires late, fires sporadically, or disappears entirely
fails the core promise of the product.

The current implementation has the worst possible failure mode for a reminder tool:

- sometimes it works
- sometimes nothing happens
- sometimes the notification appears far too late

That is worse than a consistently limited product because it trains the user not to trust the app.

We do not want to regress into "just another notification app" that gets buried with Slack and other tools. We want a
dual-path design:

- present the custom modal when the app is running, awake, and the alert is still fresh
- schedule a real macOS notification for every alert so delivery does not depend on the app process
- rely on macOS notification delivery when the app is backgrounded, sleeping, relaunched, not running, or otherwise
  unable to present custom UI safely

This keeps the product differentiated without betting reliability solely on process-local timers. Duplicate modal and
notification delivery is acceptable when necessary; a missed meeting is not.

## Current Failure Analysis

### 1. Production scheduling uses process-local timers

Production `AlertEngine` instances are created with `DispatchAlertScheduler` in
`Sources/GCalNotifier/GCalNotifierApp.swift`.

That means exact alert timing depends on:

- the app process being alive
- the app event loop and runtime being healthy
- no sleep or wake timing gaps
- no startup lag at the alert boundary
- no scheduling starvation or delayed task execution

That is not a reliable foundation for meeting reminders.

### 2. Startup can drop initial scheduling

`setupAlertEngine()` initializes the alert engine asynchronously. Sync work can begin before the alert engine exists,
which allows the first sync to load events without scheduling alerts.

This is especially dangerous at launch, login, wake, and after sign-in.

### 3. Relaunch recovery skips overdue alerts entirely

`reconcileOnRelaunch()` restores persisted alerts only if their fire time is still in the future.

That means:

- if the app was not running at the exact fire time, the alert is lost
- if the app starts shortly after the fire time, the alert is lost
- if the user logs in after a restart, the alert is lost

### 4. Wake recovery is heuristic and races stale timers

The app tries to recover on wake using `checkForMissedAlerts()`. That logic only treats alerts as actionable if:

- the meeting has not started yet, or
- the meeting started less than five minutes ago

Anything older is discarded.

Separately, the overdue dispatch timer may still resume and fire when the process wakes. That creates the observed
"hours late" class of bug: a stale timer can still invoke alert delivery after the wake path should have classified the
alert as obsolete.

### 5. Final delivery depends on cache lookup at fire time

`WindowAlertDelivery` loads the event from `EventCache` at delivery time. If the cache entry is gone or the lookup
fails, the alert is dropped.

This creates silent failures even when timing worked correctly.

### 6. Near-boundary events are intentionally skipped

The current scheduling logic only backfills a missed stage if the app notices it within a small grace window.
Anything discovered later is intentionally not scheduled.

That may be acceptable for a best-effort enhancement, but it is not acceptable as the only delivery mechanism.

## Decision

Adopt a dual-path alert architecture:

1. macOS notifications become the durable, authoritative delivery path for every scheduled alert
2. local modal triggers remain a first-class running-app path for both Stage 1 and Stage 2
3. the existing custom modal remains the preferred hard-to-miss experience when it can be shown safely
4. timer-based delivery is removed as the sole authoritative alert mechanism
5. shared alert state coordinates OS notifications, local modal triggers, snooze, join, dismiss, and cancellation

In short:

- durable delivery belongs to the OS
- hard-to-miss running-app UI belongs to the app
- state coordination belongs to `AlertEngine`

## User Experience

This plan does not intentionally turn the app into "more Slack noise."

The user experience target is:

- **Stage 1:** early warning; show the custom modal when the app is running and the alert is fresh, with a gentle
  regular OS notification as durable fallback
- **Stage 2:** urgent reminder; show the custom modal when the app is running and the alert is fresh, with a
  time-sensitive OS notification, sound, and actions as durable fallback
- **Modal delivery:** preferred for both stages when the app can present it safely
- **OS delivery:** always scheduled for both stages and never dependent on `EventCache` at fire time

This preserves the product's differentiator:

- modal-first alerts when the app is alive
- reliable OS delivery always

Recommended user-facing guidance for setup:

- enable desktop notifications for GCal Notifier
- use persistent alerts for GCal Notifier
- enable sound for GCal Notifier
- allow time-sensitive notifications for GCal Notifier
- enable and approve launch at login for GCal Notifier

That separates this app from Slack at the operating-system level because notification behavior is configured per app.
Launch-at-login is also part of the modal reliability story: if the app is not running, the modal cannot appear.

## Proposed Architecture

### Durable notification scheduler

Replace the timer-shaped production scheduler contract with a notification-specific scheduler that mirrors desired alert
state into `UNUserNotificationCenter`.

Each alert should create a visible local notification request containing enough information to notify the user and
handle actions without consulting volatile caches:

- alert id
- event id
- stage
- event title
- event start time
- event end time
- join URL if available
- calendar URL if available
- compact context string if useful
- snapshot fingerprint or version

The scheduled notification request becomes the durable, system-managed representation of the alert.

This scheduler must not expose a fire-time callback contract. Background delivery is the OS showing the notification,
not the app executing `AlertEngine.handleAlertFired()`.

### Local modal trigger scheduler

Keep a separate app-local modal trigger path for the custom popup. This trigger is intentionally best effort, but it is
still a first-class product path when the app is alive:

- schedule a local trigger for every desired alert while the app is running
- fire the modal for both Stage 1 and Stage 2 when the alert is fresh
- never treat local modal trigger delivery as the only user-visible alert
- never reconstruct missed modal triggers after sleep or relaunch
- never show a stale modal hours late

Freshness rules:

- Stage 1 modal triggers are valid only before the Stage 2 fire time for the same event
- Stage 2 modal triggers are valid only before meeting start or within a very small grace window after start
- stale local triggers no-op and leave the OS notification as the durable record

### Modal and notification coordination

If a notification fires while the app is foreground and able to present UI:

- intercept it
- show the existing modal if presentation is safe and the alert is fresh
- suppress normal banner presentation only after modal presentation is confirmed
- fail open to OS banner/list/sound if modal presentation cannot be confirmed

If a local modal trigger fires while the app is running but the app is not foreground:

- show the modal if presentation is safe and the alert is fresh
- allow the OS notification to remain as the durable fallback
- accept possible duplicate modal and notification delivery rather than risking a missed alert

Showing a modal does not acknowledge the alert and does not remove delivered OS notifications. User actions reconcile
both surfaces.

### Notification actions

Notifications for both stages should support direct user actions:

- Join
- Snooze 1 minute
- Snooze 3 minutes
- Snooze 5 minutes
- Dismiss

These actions should round-trip into `AlertEngine` so that acknowledgment and snooze behavior remain consistent across
modal and non-modal delivery paths.

Action behavior:

- default notification activation opens or focuses the app and shows the relevant alert context when still relevant
- Join opens the meeting URL and acknowledges only that alert stage
- Dismiss acknowledges only that alert stage
- Snooze replaces the current alert request and local modal trigger with a new fire time
- snoozing Stage 1 must not move it to or past the Stage 2 fire time
- unavailable snooze durations should be hidden or disabled in both the modal and notification actions

Use a small fixed set of notification category variants for action capabilities rather than generating per-alert
categories. Alert-specific data belongs in notification `userInfo`.

### Persistence model

`ScheduledAlertsStore` should evolve from a persisted list of scheduled timers into persisted desired alert records.
The model may remain named `ScheduledAlert` during early migration, but the domain concept should become an alert record
or alert state.

Instead:

- the store records intended alert state for reconciliation and recovery
- `NotificationScheduler` mirrors that state into `UNUserNotificationCenter`
- the local modal trigger scheduler mirrors that state while the app is running
- relaunch recovery checks and reconciles alert records against pending and delivered notification state
- user actions transition alert records and remove or replace both OS and modal effects

### Wake and relaunch behavior

After migration, wake and relaunch logic should be simplified:

- wake triggers an immediate sync and schedule reconciliation
- relaunch triggers schedule reconciliation against persisted desired state
- neither path should be responsible for "guessing" missed exact-time modal delivery using best-effort heuristics
- neither path should show stale modal alerts

The OS should already have handled durable user-visible delivery if the scheduled time occurred while the app was
inactive. Delivered OS notifications should remain visible until user action or explicit invalidation; they should not
be removed merely because their fire time is in the past.

## Migration Plan

### Phase 0: Immediate hardening before backend swap

Ship fast reliability improvements that reduce obvious failures in the current implementation:

- make alert-engine readiness explicit so first sync cannot race initialization
- guard against stale timer delivery after wake
- log and surface dropped delivery cases instead of silently losing them
- consider backfilling relaunch handling for recently overdue alerts until the OS scheduler is in place
- make local modal triggers wall-clock fresh so they cannot show hours late

This phase reduces current pain while the larger migration is in progress.

### Phase 1: Introduce alert records and dual schedulers

Replace the timer-shaped scheduler contract before changing UX behavior:

- evolve `ScheduledAlert` toward an alert record with a full presentation snapshot
- split durable notification scheduling from local modal trigger scheduling
- schedule both Stage 1 and Stage 2 through the OS-backed notification path
- schedule both Stage 1 and Stage 2 through the local modal trigger path while the app is running
- add stale-trigger guards before any modal can be shown
- make startup block initial sync until alert scheduling is ready

This phase should eliminate the most dangerous "never fired" cases while preserving the custom modal when the app is
alive.

### Phase 2: Add notification actions and state coordination

Once both delivery paths exist:

- add action-capability category variants for Join, Snooze, and Dismiss
- route notification actions into explicit `AlertEngine` commands
- keep acknowledgments stage-specific
- make Join acknowledge the current alert stage
- make Snooze replace pending and delivered OS notification state plus local modal triggers
- prevent Stage 1 snooze from overlapping Stage 2
- close or no-op stale modals when notification actions mutate the same alert
- remove pending and delivered notifications when user action resolves an alert

At this point modal actions and notification actions should behave consistently.

### Phase 3: Reconciliation, diagnostics, and cleanup

After the OS-backed scheduler is proven:

- reconcile desired alert records against pending OS requests, delivered notifications, and local modal triggers
- replace pending OS requests when fire time or snapshot fields change
- preserve delivered notifications during generic cleanup
- remove delivered notifications when events are canceled, declined, deleted, no longer alertable, acknowledged, snoozed,
  or superseded
- trigger reconciliation from settings changes that affect timing or eligibility
- add structured per-alert diagnostics
- simplify missed-alert wake heuristics
- simplify relaunch recovery
- remove code paths that exist only to compensate for process-local timing

The code should become smaller and easier to reason about after this phase because OS notifications, local modal
triggers, and alert state have separate responsibilities.

## Implementation Notes

### Data model changes

Extend `ScheduledAlert` or replace it with an alert-record model that includes a minimal presentation snapshot so
delivery does not depend on cache lookup:

- `eventTitle`
- `eventStartTime`
- `eventEndTime`
- `joinURL`
- `htmlLink`
- `contextLine` or equivalent
- notification payload fingerprint/version
- delivery state such as scheduled, presented, snoozed, acknowledged, canceled, or expired

The app can still refresh from cache when available, but it should not require cache presence to alert.

State must coordinate the modal and OS notification surfaces. Showing a modal is not acknowledgment. Join, Dismiss, and
Snooze are commands that transition alert state and reconcile both surfaces.

### Scheduler contracts

Replace the existing `AlertScheduler.schedule(alertId:fireDate:handler:)` shape with two explicit dependencies:

- durable notification scheduling that creates, replaces, cancels, and reconciles `UNNotificationRequest` state without a
  fire-time callback contract
- local modal trigger scheduling that may call back while the app is running, but is allowed to miss and must no-op when
  stale

The notification scheduler needs APIs to inspect pending requests and to remove delivered notifications by identifier.
The local modal trigger scheduler must never be used as the sole production delivery path.

### App lifecycle ordering

Initialization ordering must change so that:

- notification categories are registered before scheduling
- notification delegate wiring is ready before the first sync
- the first reconcile cannot run until the scheduler path is fully available
- launch-at-login status is visible in reliability diagnostics
- notification permission denial puts the app into an explicit degraded state rather than silently falling back to timers

### Reconciliation rules

Reconciliation should be set-based and bidirectional:

- desired future alert records should have pending OS notification requests
- desired alert records should have local modal triggers while the app is running
- extra pending OS requests for this app should be removed
- pending requests with stale fire times or stale snapshots should be replaced
- delivered notifications should be preserved during generic cleanup
- delivered notifications should be removed when the alert is acknowledged, snoozed, canceled, or invalidated by event or
  settings changes
- settings changes that affect timing or eligibility should reconcile from cached events immediately

"Still relevant" should use the existing `EventFilter.shouldAlert` rules. All-day, declined, missing-link without
force-alert keyword, disabled calendar, and blocked keyword changes invalidate alert records.

### Settings and onboarding

Update onboarding and settings copy to explain why notification settings matter:

- GCal Notifier should be configured separately from Slack
- Stage 2 benefits from persistent and time-sensitive notification settings
- launch at login controls how often the modal path is available
- if users disable OS notifications entirely, reliability is impossible by design
- if users disable launch at login, modal availability after reboot/login is degraded

### Telemetry and diagnostics

Even without external analytics, local logs should make failures diagnosable:

- desired alert created, updated, or removed
- OS notification scheduled, replaced, or canceled
- local modal trigger scheduled, replaced, canceled, fired, stale, or no-op
- modal shown, failed, or suppressed
- OS fallback used
- action taken from notification
- action taken from modal
- state transition applied
- delivery dropped and why

This is necessary to debug the next class of failures without guesswork.

## Acceptance Criteria

The migration is successful when all of the following are true:

- Stage 1 and Stage 2 OS notifications are scheduled with complete user-visible payloads
- Stage 2 OS notifications are time-sensitive where supported
- a Stage 2 alert still appears on time if the app is backgrounded
- a Stage 2 alert still appears on time if the Mac sleeps and wakes near the alert boundary
- a Stage 2 alert is not lost if the app relaunches shortly before or after the alert boundary
- a stale local modal never appears hours late
- the custom modal appears for both stages when the app is running, awake, and the alert is fresh
- background delivery never depends on `EventCache` to render the user-visible alert
- Join, Snooze, and Dismiss work consistently from both the modal and notification actions
- dismissing Stage 1 never suppresses Stage 2
- snoozing Stage 1 cannot overlap or pass the Stage 2 fire time
- settings changes immediately reconcile alert timing and eligibility from cached events
- launch-at-login and notification-permission problems are surfaced as reliability diagnostics

## Non-Goals

This plan does not aim to:

- preserve the exact same visual delivery path in every runtime state
- make local modal triggers the sole authoritative alert path
- keep `DispatchAlertScheduler` as a hidden reliability fallback
- make Stage 1 as urgent as Stage 2 at the OS notification level
- solve every calendar-sync issue unrelated to alert delivery

## Risks

### Risk: Users may still configure weak OS notification settings

Mitigation:

- surface setup guidance in onboarding and settings
- warn clearly when notifications are disabled or configured weakly

### Risk: The local modal trigger path remains lifecycle-limited

Mitigation:

- keep OS notifications as the durable fallback
- treat launch at login as a reliability setting
- use strict freshness checks so local triggers cannot show stale modals

### Risk: Migration complexity around actions and reconciliation

Mitigation:

- separate notification scheduling from local modal trigger scheduling
- keep the notification category matrix small and fixed
- add focused tests around foreground, background, wake, relaunch, actions, and reconciliation

## Suggested Work Breakdown

1. Stabilize initialization ordering and stale-alert handling in the current implementation.
2. Extend or replace `ScheduledAlert` with alert-record state and complete presentation snapshots.
3. Split durable notification scheduling from local modal trigger scheduling.
4. Schedule both Stage 1 and Stage 2 as real OS notifications.
5. Schedule both Stage 1 and Stage 2 through local modal triggers while the app is running.
6. Add freshness checks before modal presentation.
7. Add notification categories and actions for Join, Snooze, and Dismiss.
8. Route modal and notification actions through the same alert-state commands.
9. Add set-based reconciliation for alert records, pending OS requests, delivered notifications, and modal triggers.
10. Reconcile immediately when alert-affecting settings change.
11. Add reliability diagnostics for notification permission and launch at login.
12. Remove timer-era missed-alert recovery code that conflicts with the OS-backed model.

## Recommended File Touches

Primary files expected to change during implementation:

- `Sources/GCalNotifier/GCalNotifierApp.swift`
- `Sources/GCalNotifier/AppDelegate+Sync.swift`
- `Sources/GCalNotifier/Alerts/WindowAlertDelivery.swift`
- `Sources/GCalNotifierCore/Alerts/AlertEngine.swift`
- `Sources/GCalNotifierCore/Alerts/AlertScheduler.swift`
- `Sources/GCalNotifierCore/Alerts/NotificationScheduler.swift`
- `Sources/GCalNotifierCore/Alerts/AlertTypes.swift`
- `Sources/GCalNotifierCore/Data/ScheduledAlertsStore.swift`
- `Sources/GCalNotifier/System/NotificationPermissionHandler.swift`
- `Sources/GCalNotifier/System/LaunchAtLoginManager.swift`
- `Sources/GCalNotifier/Settings/PreferencesView.swift`
- `Tests/GCalNotifierTests/Alerts/NotificationSchedulerTests.swift`
- `Tests/GCalNotifierTests/Alerts/AlertEngineReconcileTests.swift`
- `Tests/GCalNotifierTests/Alerts/AlertEngineMissedAlertsTests.swift`
- `Tests/GCalNotifierTests/Alerts/AlertEngineSnoozeTests.swift`
- `Tests/GCalNotifierTests/System/NotificationPermissionHandlerTests.swift`

## Final Recommendation

Do not continue hardening the current timer-only model as the long-term strategy.

Small fixes are worth shipping immediately, but the core reliability issue is architectural: production alert timing is
owned only by the app process instead of being backed by macOS.

The durable fix is to schedule real OS notifications for every alert and keep a hardened local modal trigger as a
first-class running-app experience. The modal is the product differentiator; the OS notification is the reliability
floor.
