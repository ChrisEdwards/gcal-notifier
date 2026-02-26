---
date: 2026-02-26
topic: calendar-filter-checkboxes
bead: gcn-3m4
---

# Calendar Filter: Checkbox UI to Enable/Disable Calendars

## What We're Building

Replace the current Calendars tab in Preferences — which requires manually typing calendar IDs — with a live checkbox list. The app will fetch the user's actual Google calendars by name and show each one with a toggle. Unchecking a calendar excludes its events from meeting alerts. The calendar list is cached in UserDefaults so the tab renders immediately even when offline, then refreshes once a fresh API response arrives.

## Why This Approach

**Approach A (chosen):** Checkbox list with persistent cache, keeping the existing `enabledCalendars: [String]` data model. The "empty = all" semantic already threaded through `EventFilter` and `SyncEngine` remains unchanged — no backend rewiring needed.

**Approach B (rejected):** Inverting to a `disabledCalendars` list. Semantically cleaner but requires touching `EventFilter`, `SettingsStore`, `SyncEngine`, and a settings migration. Not worth it for no UX gain.

## Key Decisions

- **Replace, don't augment:** Remove the manual ID entry UI entirely. Checkboxes are the only way to manage calendar selection.
- **"Empty = all" preserved:** When all calendars are checked, `enabledCalendars` stores `[]` (unchanged from today). When some are unchecked, `enabledCalendars` stores the IDs of the *checked* ones.
- **Cache calendar display names:** Add `cachedCalendarList: [CalendarInfo]` to `SettingsStore` (JSON-encoded, same pattern as other arrays). Shown immediately on tab open; refreshed in the background on each open.
- **Fetch on tab open:** Trigger `GoogleCalendarClient.fetchCalendarList()` when the Calendars tab appears. No polling or background refresh.
- **Loading state:** Show cached list immediately (or a spinner if no cache yet). Update in place when fresh data arrives.
- **Error state:** If fetch fails and no cache exists, show a brief error message with a Retry button.

## Existing Code to Reuse

| What | Where |
|------|-------|
| `fetchCalendarList()` | `GoogleCalendarClient.swift` |
| `CalendarInfo` struct (id, summary, isPrimary) | `GoogleCalendarClient.swift` |
| `enabledCalendars: [String]` setting | `SettingsStore.swift` |
| Calendars tab | `PreferencesView.swift` (lines ~322–391) |
| JSON encode/decode pattern | `SettingsStore.swift` (used for all array settings) |

## Scope

**In scope:**
- Replace the Calendars tab manual entry with a checkbox list
- Cache calendar list for offline display
- Background refresh on each tab open

**Out of scope:**
- Calendar colors (not in `CalendarInfo` today)
- Multiple Google accounts
- Drag-to-reorder calendars
- Per-calendar alert settings

## Open Questions

*(none — all resolved during brainstorm)*

## Resolved Questions

- **Replace or augment manual entry?** → Replace entirely.
- **Offline/fetch failure behavior?** → Show last known cached list.
- **Data model change?** → No, keep `enabledCalendars` with existing "empty = all" semantic.

## Next Steps

→ `/workflows:plan` to produce an implementation plan for this feature.
