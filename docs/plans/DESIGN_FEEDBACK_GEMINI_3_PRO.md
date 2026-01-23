This is a solid foundation for a "scratch your own itch" tool. The architecture is clean, and the scope is well-defined. However, relying on a fixed 5-minute poll and strict "no video link" filtering introduces reliability risks for critical meetings.

Here are 4 specific revisions to improve API efficiency, data reliability, alert logic, and usability.

---

### 1. Architecture: Incremental Sync (`syncToken`)

**Analysis & Rationale:**
The current plan fetches all events for the next 24 hours every 5 minutes using `timeMin`. This is inefficient and computationally wasteful. Google Calendar API specifically supports **Incremental Sync** via `syncToken`.

* **Why it's better:**
* **Performance:** Drastically reduces payload size (Google only returns what changed).
* **Quota Safety:** Reduces the risk of hitting Google API quotas if you decide to lower the polling interval later.
* **Robustness:** It is the "correct" way to handle state synchronization with Google Calendar.
* **Handling Deletes:** The current `timeMin` fetch makes detecting deleted events harder (you have to diff the array). `syncToken` responses explicitly list deleted event IDs.



**Git-Diff:**

````diff
 ### API Usage
 
 Primary endpoint for fetching events:
 

```

GET [https://www.googleapis.com/calendar/v3/calendars/](https://www.googleapis.com/calendar/v3/calendars/){calendarId}/events

* ?timeMin={now}
* &timeMax={now + 24h}

* ?singleEvents=true
&orderBy=startTime
* &syncToken={stored_token} (if available)
* OR
* &timeMin={now} &timeMax={now + 24h} (initial sync only)

```

-Calendar list endpoint (for settings):
+**Sync Strategy:**
+1. **Initial Load:** Fetch full 24h window, store `nextSyncToken`.
+2. **Subsequent Polls:** Pass `syncToken`. API returns only new/modified/deleted events.
+3. **Token Expiry:** If API returns `410 Gone`, clear token and perform full initial load.
+
+Calendar list endpoint (for settings):

````

---

### 2. Logic: "Force Alert" Keywords (Allow-list)

**Analysis & Rationale:**
The "No video link = no alert" rule is too aggressive. You will inevitably miss a critical in-person interview, a phone call, or a meeting where the link is in the body text but regex fails.

* **Why it's better:**
* **Reliability:** Allows you to manually flag events as "Critical" even if the automation fails to find a link.
* **Flexibility:** Supports hybrid workflows (some meetings are physical, some digital).



**Git-Diff:**

```diff
    @AppStorage("enabledCalendars") var enabledCalendars: [String] = []
    @AppStorage("blockedKeywords") var blockedKeywords: [String] = []
+   @AppStorage("forceAlertKeywords") var forceAlertKeywords: [String] = ["IMPORTANT", "Interview"]
 
    // Polling
    @AppStorage("pollIntervalMinutes") var pollIntervalMinutes: Int = 5
 }
 
...
 
 ### Filtering Logic
 
 Events must pass all filters to trigger alerts:
 
-1. **Has video link** (automatic) - Event must have extractable meeting URL
+1. **Has video link OR Force Keyword** - Event has URL, or title contains keyword (e.g., "Interview")
 2. **Calendar enabled** (manual) - Event's calendar must be in enabled list
 3. **No blocked keywords** (manual) - Event title must not contain any blocked keywords

```

---

### 3. Feature: Global "Instant Join" Hotkey

**Analysis & Rationale:**
The design relies on waiting for the modal or clicking the menu bar. Often, you realize you are late and just want to "teleport" into the meeting immediately without navigating UI.

* **Why it's better:**
* **Speed:** A global hotkey (e.g., `Cmd+Shift+J`) reduces friction to zero.
* **Compelling:** This is a power-user feature that makes the app feel "pro."
* **Implementation:** You already have `KeyboardShortcuts` in your dependencies; this leverages it fully.



**Git-Diff:**

```diff
 | Package | Purpose |
 |---------|---------|
-| KeyboardShortcuts (sindresorhus) | Optional global hotkeys |
+| KeyboardShortcuts (sindresorhus) | Global hotkey for "Join Next Meeting" |
 | swift-log (Apple) | Structured logging |
 
...
 
 ### Menu Bar UI
 
...
 
 | Within alert window (< 10 min) | Icon pulses/highlights |
 
+### Global Hotkeys
+
+- **Join Next Meeting:** Opens the video link for the nearest upcoming meeting (if < 15 min away).
+- **Snooze Alert:** Dismisses currently visible modal.
+
 ### Menu Content 

```

---

### 4. Architecture: Adaptive "Smart" Polling
**Analysis & Rationale:**
A fixed 5-minute poll is risky. If a colleague adds you to a "Quick sync" meeting happening in 2 minutes, a 5-minute timer might miss the start time entirely. Conversely, polling every 5 minutes at 3:00 AM is wasteful.

* **Why it's better:**
    * **Responsiveness:** Increases poll frequency when a meeting is imminent to catch last-minute link updates or cancellations.
    * **Efficiency:** Relaxes polling when the calendar is empty.

**Git-Diff:**

```diff
 ### Polling Strategy
 
-- Full refresh every 5 minutes (configurable)
+- **Adaptive Interval:**
+  - Default: Every 15 minutes.
+  - If meeting within 1 hour: Every 5 minutes.
+  - If meeting within 10 minutes: Every 1 minute (to catch link updates).
 - On wake from sleep: immediate refresh
 - After dismissing an alert: refresh to catch any changes

```

---

### 5. UX: Presentation Mode Safety

**Analysis & Rationale:**
The design calls for `level: .floating` (appearing above all windows). If you are screen sharing or presenting a slide deck, a giant modal popping up saying "Meeting in 10 mins" is embarrassing and disruptive.

* **Why it's better:**
* **Professionalism:** Prevents the app from interrupting other work presentations.
* **Safety:** Ensures the modal doesn't steal focus while you are typing in another critical window.



**Git-Diff:**

```diff
 | Multiple meetings at same time | Show one modal per meeting, stack them |
-| User in Do Not Disturb | Alerts still fire (NSPanel ignores DND) |
+| User in Do Not Disturb | Alert suppressed (Sound only or Banner only) |
+| **Screen Sharing / Mirroring** | **Suppress Modal**, stick to Menu Bar pulse & sound |
 
 ### Wake from Sleep

```

### Next Step

Would you like me to generate the **Swift code for the `CalendarPoller**` incorporating the `syncToken` logic and the adaptive interval strategy?