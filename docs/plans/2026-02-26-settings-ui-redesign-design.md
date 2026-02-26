# Settings UI Redesign

## Problem

The settings window is 500x400 with 6 tabs. Several tabs overflow without visible scroll affordance, making content hidden and undiscoverable. The AccountTab nests a Form inside a ScrollView inside a VStack, creating structural messiness. The overall experience feels cramped and ugly.

## Solution

Replace the TabView with a NavigationSplitView sidebar layout and increase the window to 650x550.

## Design Decisions

- **NavigationSplitView** over custom HSplitView — native macOS behavior, less code, accessibility built-in
- **Keep all 6 sections** — sidebar has room, no need to consolidate
- **650x550 window** — enough space for content to breathe, Account/OAuth fits without scrolling
- **Reuse existing section views** — GeneralTab, SoundsTab, CalendarsTab, FilteringTab, ShortcutsTab stay as-is
- **Restructure AccountTab** — single Form instead of OAuthSetupView-with-its-own-Form nested in ScrollView

## Navigation Structure

```swift
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, sounds, calendars, filtering, shortcuts, account
    var id: String { rawValue }
}
```

Sidebar: List with ForEach over SettingsSection.allCases, each with icon + label.
Detail: switch on selected section, render the corresponding view.

## File Changes

1. **PreferencesView.swift** — Replace TabView body with NavigationSplitView. Add SettingsSection enum. Add sidebar + detail views.
2. **OAuthSetupView.swift** — Restructure AccountTab to use single Form. Inline OAuth content or refactor OAuthSetupView to not carry its own Form.
3. **GCalNotifierApp.swift** — Update window size from 500x400 to 650x550.

## Window Layout

```
┌──────────────────────────────────────────────────────────────┐
│ GCalNotifier Settings                                        │
├──────────────┬───────────────────────────────────────────────┤
│              │                                               │
│  ⚙ General   │   Content area (~480px wide)                  │
│  🔊 Sounds   │   Each section renders its Form here          │
│  📅 Calendars│   with natural scrolling                      │
│  ⊘ Filtering │                                               │
│  ⌨ Shortcuts │                                               │
│  👤 Account  │                                               │
│              │                                               │
│  (~160px)    │                                               │
└──────────────┴───────────────────────────────────────────────┘
```

Window: 650x550, closable only, centered on screen.
