---
title: "feat: Calendar filter checkbox UI to enable/disable individual calendars"
type: feat
status: completed
date: 2026-02-26
origin: docs/brainstorms/2026-02-26-calendar-filter-checkboxes-brainstorm.md
bead: gcn-3m4
---

# feat: Calendar Filter Checkbox UI

## Overview

Replace the manual calendar ID entry in Preferences → Calendars tab with a live checkbox list. The app fetches the user's Google calendars by display name and shows each as a toggle. Unchecking a calendar excludes its events from meeting alerts. The list is cached in UserDefaults so the tab renders instantly even when offline.

## Problem Statement

The current Calendars tab requires users to know and type their calendar IDs (email addresses) manually. There is no way to discover what calendars are available, and the empty-state "All calendars enabled" gives no actionable path to filter. This makes calendar filtering effectively unusable.

## Proposed Solution

Replace `CalendarsTab` (lines 319–391, `PreferencesView.swift`) with a new implementation that:

1. Fetches the real calendar list via `GoogleCalendarClient.fetchCalendarList()` on tab open
2. Caches the result in `SettingsStore.cachedCalendarList` (UserDefaults, JSON-encoded) for offline/re-open use
3. Renders each calendar as a `Toggle` row — checked = included in alerts
4. Writes selection back to `SettingsStore.enabledCalendars`, preserving the existing "empty = all" semantic throughout the rest of the system

## Technical Considerations

### "Empty = All" Semantic (Preserved)

The existing `EventFilter` and `resolveCalendarIdsForSync` both read `enabledCalendars: [String]` with the invariant: **empty array → all calendars enabled**. This invariant is **not changed**. The new UI maps to it as follows:

- All calendars checked → `enabledCalendars = []`
- Some unchecked → `enabledCalendars = [IDs of checked calendars only]`

### Last-Calendar Guard

If only one calendar is effectively checked and the user unchecks it, the result would be `[]` — which means ALL, the opposite of intent. **Solution: disable the toggle for the last checked calendar** and show a brief tooltip or `.help("At least one calendar must be selected.")`. This preserves data model correctness without introducing a new semantic concept.

### Fetch Ownership — Closure Injection

`GoogleCalendarClient` lives on `AppDelegate` and is not accessible from `CalendarsTab`. Rather than threading the client through the view hierarchy (which crosses the module boundary), inject a **fetch closure** into `CalendarsTab`:

```swift
let fetchCalendars: () async throws -> [CalendarInfo]
```

This mirrors the existing `onForceSync: (() async -> ForceSyncResult)?` pattern in `PreferencesView`. The closure is provided at call site in `showSettingsWindow()`.

### Two Caches — Separate Concerns

`AppDelegate.cachedCalendarIds: [String]` (in-memory, IDs only) and the new `SettingsStore.cachedCalendarList: [CalendarInfo]` (persistent, includes display names) serve different purposes and are not unified. The sync resolution logic remains unchanged; `cachedCalendarList` is UI-only.

### Sort Order

Display calendars: **primary first**, then alphabetical by `summary`. The `CalendarInfo.isPrimary` field drives the primary-first sort.

### Orphan IDs

If `enabledCalendars` contains an ID not present in `cachedCalendarList` (deleted Google calendar), it is **silently ignored in the UI** — no phantom rows, no warning. The orphan ID is removed from `enabledCalendars` when the user next makes any toggle change (natural reconciliation).

### New Calendars During Refresh

If a live fetch discovers a new calendar not in `enabledCalendars` (when it is non-empty / explicit selection mode), the new calendar **appears unchecked**. The user must explicitly check it. This is the expected behavior for an explicit selection.

### Error / Stale Cache Behavior

| Fetch result | Cache exists | UI behavior |
|---|---|---|
| Success | any | Update list in place; update cache |
| Failure | yes | Show cached list silently; no error surfaced |
| Failure | no | Show error message + Retry button |

No "last updated" timestamp or refresh indicator is shown — keep it simple.

## Files Changed

| File | Change |
|------|--------|
| `Sources/GCalNotifierCore/Calendar/GoogleCalendarTypes.swift` | Add `Codable` to `CalendarInfo` |
| `Sources/GCalNotifierCore/Settings/SettingsStore.swift` | Add `cachedCalendarList` property + generic `Codable` array helpers |
| `Sources/GCalNotifier/Settings/PreferencesView.swift` | Replace `CalendarsTab` struct (lines 319–391); add `fetchCalendars` closure to `PreferencesView.init` and thread it through to `CalendarsTab` |
| `Sources/GCalNotifier/GCalNotifierApp.swift` | Pass `fetchCalendars` closure to `PreferencesView` in `showSettingsWindow()` |

## Implementation Steps

### Step 1 — Make `CalendarInfo` Codable

**File:** `Sources/GCalNotifierCore/Calendar/GoogleCalendarTypes.swift`

Add `Codable` to the conformance list of `CalendarInfo` and `CalendarAccessRole`. Both are value types with only standard-type fields so synthesis is automatic.

```swift
// Before
public struct CalendarInfo: Sendable, Equatable { ... }
public enum CalendarAccessRole: String, Sendable { ... }

// After
public struct CalendarInfo: Codable, Sendable, Equatable { ... }
public enum CalendarAccessRole: String, Codable, Sendable { ... }
```

### Step 2 — Add `cachedCalendarList` to SettingsStore

**File:** `Sources/GCalNotifierCore/Settings/SettingsStore.swift`

Add a new key and two generic helpers (to complement the existing `loadStringArray`/`saveStringArray` which only handle `[String]`):

```swift
// In Keys enum
static let cachedCalendarList = "cachedCalendarList"

// New generic helpers
private func loadCodableArray<T: Codable>(forKey key: String) -> [T] {
    guard let jsonString = defaults.string(forKey: key),
          let data = jsonString.data(using: .utf8)
    else { return [] }
    return (try? JSONDecoder().decode([T].self, from: data)) ?? []
}

private func saveCodableArray<T: Codable>(_ array: [T], forKey key: String) {
    guard let data = try? JSONEncoder().encode(array),
          let jsonString = String(data: data, encoding: .utf8) else { return }
    defaults.set(jsonString, forKey: key)
}

// New property
public var cachedCalendarList: [CalendarInfo] {
    get {
        access(keyPath: \.cachedCalendarList)
        return loadCodableArray(forKey: Keys.cachedCalendarList)
    }
    set {
        withMutation(keyPath: \.cachedCalendarList) {
            saveCodableArray(newValue, forKey: Keys.cachedCalendarList)
        }
    }
}
```

### Step 3 — Replace CalendarsTab in PreferencesView

**File:** `Sources/GCalNotifier/Settings/PreferencesView.swift`

#### 3a. Update `PreferencesView` init

Add `fetchCalendars` parameter (optional, defaulting to `nil` for previews/tests):

```swift
// Add stored property
private let fetchCalendars: (() async throws -> [CalendarInfo])?

// Update init signature
init(
    settings: SettingsStore = SettingsStore(),
    oauthProvider: GoogleOAuthProvider = GoogleOAuthProvider(),
    fetchCalendars: (() async throws -> [CalendarInfo])? = nil,
    onForceSync: (() async -> ForceSyncResult)? = nil
)
```

Update the `TabView` call site (line ~28) to forward the closure:

```swift
CalendarsTab(settings: self.settings, fetchCalendars: self.fetchCalendars)
    .tabItem { Label("Calendars", systemImage: "calendar") }
```

#### 3b. Replace `CalendarsTab` struct (lines 319–391)

Replace the entire `// MARK: - Calendars Tab` block with:

```swift
// MARK: - Calendars Tab

struct CalendarsTab: View {
    @Bindable var settings: SettingsStore
    let fetchCalendars: (() async throws -> [CalendarInfo])?

    @State private var isLoading = false
    @State private var fetchFailed = false

    // Sorted display list: primary first, then alphabetical
    private var displayedCalendars: [CalendarInfo] {
        settings.cachedCalendarList.sorted {
            if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
            return $0.summary < $1.summary
        }
    }

    // Count of calendars that are currently checked
    private var checkedCount: Int {
        if settings.enabledCalendars.isEmpty { return displayedCalendars.count }
        return displayedCalendars.filter { settings.enabledCalendars.contains($0.id) }.count
    }

    var body: some View {
        Form {
            Section {
                Text("Select which calendars should trigger meeting alerts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Calendars") {
                if displayedCalendars.isEmpty && isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading calendars…").foregroundStyle(.secondary)
                    }
                } else if displayedCalendars.isEmpty && fetchFailed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Could not load calendars.")
                            .foregroundStyle(.secondary)
                        Button("Retry") { Task { await refresh() } }
                    }
                } else {
                    ForEach(displayedCalendars) { calendar in
                        Toggle(isOn: isEnabled(calendar)) {
                            if calendar.isPrimary {
                                HStack(spacing: 4) {
                                    Text(calendar.summary)
                                    Text("(Primary)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text(calendar.summary)
                            }
                        }
                        .disabled(checkedCount == 1 && isEnabled(calendar).wrappedValue)
                        .help(checkedCount == 1 && isEnabled(calendar).wrappedValue
                              ? "At least one calendar must be selected."
                              : "")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
    }

    private func isEnabled(_ calendar: CalendarInfo) -> Binding<Bool> {
        Binding(
            get: {
                settings.enabledCalendars.isEmpty
                    || settings.enabledCalendars.contains(calendar.id)
            },
            set: { checked in
                if checked {
                    var enabled = settings.enabledCalendars
                    if !enabled.contains(calendar.id) { enabled.append(calendar.id) }
                    // Collapse to empty (all) if every displayed calendar is now checked
                    let allIds = Set(displayedCalendars.map(\.id))
                    settings.enabledCalendars = Set(enabled).isSuperset(of: allIds) ? [] : enabled
                } else {
                    // Expand from "all" to explicit list, then remove this calendar
                    var enabled = settings.enabledCalendars.isEmpty
                        ? displayedCalendars.map(\.id)
                        : settings.enabledCalendars
                    enabled.removeAll { $0 == calendar.id }
                    settings.enabledCalendars = enabled
                }
            }
        )
    }

    private func refresh() async {
        guard let fetch = fetchCalendars else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let calendars = try await fetch()
            settings.cachedCalendarList = calendars
            // Reconcile: remove orphan IDs from enabledCalendars
            if !settings.enabledCalendars.isEmpty {
                let validIds = Set(calendars.map(\.id))
                settings.enabledCalendars = settings.enabledCalendars.filter { validIds.contains($0) }
            }
            fetchFailed = false
        } catch {
            if settings.cachedCalendarList.isEmpty { fetchFailed = true }
            // Silently retain stale cache if it exists
        }
    }
}
```

Note: `CalendarInfo` needs `Identifiable` for `ForEach`. Add `Identifiable` conformance using `id` (already a `String` field):

```swift
// GoogleCalendarTypes.swift
public struct CalendarInfo: Codable, Identifiable, Sendable, Equatable { ... }
```

### Step 4 — Wire up in GCalNotifierApp

**File:** `Sources/GCalNotifier/GCalNotifierApp.swift`

In `showSettingsWindow()`, pass the fetch closure:

```swift
// Before
let prefs = PreferencesView(
    settings: self.settingsStore,
    oauthProvider: self.oauthProvider,
    onForceSync: { ... }
)

// After
let prefs = PreferencesView(
    settings: self.settingsStore,
    oauthProvider: self.oauthProvider,
    fetchCalendars: { [weak self] in
        guard let client = self?.calendarClient else { return [] }
        return try await client.fetchCalendarList()
    },
    onForceSync: { ... }
)
```

## Acceptance Criteria

- [x] Calendars tab shows a `Toggle` row for each Google calendar by display name
- [x] Primary calendar is listed first with a "(Primary)" label; remaining calendars are sorted alphabetically
- [x] All calendars are checked by default (new install or all previously checked)
- [x] Unchecking a calendar removes it from meeting alerts on the next sync cycle
- [x] Re-checking all calendars saves `enabledCalendars = []` (verified in UserDefaults)
- [x] The last checked calendar's toggle is disabled; a `.help()` tooltip explains why
- [x] On first open (no cache): loading spinner shown, then list populates after fetch
- [x] On subsequent opens: cached list renders immediately; live fetch updates in place
- [x] When fetch fails with no cache: error message and Retry button are shown
- [x] When fetch fails with cache present: stale list is shown silently; no error banner
- [x] Calendar list is persisted to UserDefaults and survives app restart
- [x] Orphan IDs (deleted Google calendars) are removed from `enabledCalendars` on successful fetch
- [x] `make check-test` passes

## System-Wide Impact

- **EventFilter**: No changes — reads `enabledCalendars` exactly as before; "empty = all" invariant preserved.
- **SyncEngine / resolveCalendarIdsForSync**: No changes — still reads `enabledCalendars` and `cachedCalendarIds` (the in-memory AppDelegate cache). The new `cachedCalendarList` in `SettingsStore` is UI-only.
- **SettingsStore**: Additive only — new property + helpers. No existing keys modified.
- **GoogleCalendarTypes.swift**: Additive only — `Codable` and `Identifiable` added. Binary-compatible change.
- **PreferencesView**: Init gains optional parameter with default `nil` — existing call sites (tests, previews) continue to compile unchanged.

## Sources

- **Origin brainstorm:** [docs/brainstorms/2026-02-26-calendar-filter-checkboxes-brainstorm.md](../brainstorms/2026-02-26-calendar-filter-checkboxes-brainstorm.md) — Key decisions carried forward: replace manual entry entirely; "empty = all" preserved; fetch closure injection pattern.
- `Sources/GCalNotifier/Settings/PreferencesView.swift:319–391` — CalendarsTab to replace
- `Sources/GCalNotifierCore/Settings/SettingsStore.swift` — persistence pattern to follow
- `Sources/GCalNotifierCore/Calendar/GoogleCalendarClient.swift` — `fetchCalendarList()` and `CalendarInfo`
- `Sources/GCalNotifier/GCalNotifierApp.swift` — `showSettingsWindow()` call site
