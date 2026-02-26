# Settings UI Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the cramped 500x400 TabView settings window with a 650x550 sidebar navigation layout for a delightful UX.

**Architecture:** NavigationSplitView with sidebar enum driving detail pane content. Existing tab content views reused with minimal changes. AccountTab restructured to eliminate nested Form/ScrollView.

**Tech Stack:** SwiftUI, NavigationSplitView (macOS 13+, we target macOS 15)

---

### Task 1: Add SettingsSection enum and convert PreferencesView to sidebar layout

**Files:**
- Modify: `Sources/GCalNotifier/Settings/PreferencesView.swift:1-45`

**Step 1: Add the SettingsSection enum**

Add this enum above `PreferencesView`:

```swift
/// Sidebar sections for the settings window.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case sounds
    case calendars
    case filtering
    case shortcuts
    case account

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: "General"
        case .sounds: "Sounds"
        case .calendars: "Calendars"
        case .filtering: "Filtering"
        case .shortcuts: "Shortcuts"
        case .account: "Account"
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .sounds: "speaker.wave.2"
        case .calendars: "calendar"
        case .filtering: "line.3.horizontal.decrease.circle"
        case .shortcuts: "keyboard"
        case .account: "person.circle"
        }
    }
}
```

**Step 2: Replace the TabView body with NavigationSplitView**

Replace the entire `body` of `PreferencesView` with:

```swift
var body: some View {
    NavigationSplitView {
        List(SettingsSection.allCases, selection: self.$selectedSection) { section in
            Label(section.label, systemImage: section.icon)
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 170, max: 200)
    } detail: {
        self.detailView
    }
    .frame(width: 650, height: 550)
}
```

Add a `@State` property to `PreferencesView`:

```swift
@State private var selectedSection: SettingsSection? = .general
```

**Step 3: Add the detail view switch**

Add this computed property to `PreferencesView`:

```swift
@ViewBuilder
private var detailView: some View {
    switch self.selectedSection {
    case .general:
        GeneralTab(settings: self.settings)
    case .sounds:
        SoundsTab(settings: self.settings)
    case .calendars:
        CalendarsTab(settings: self.settings, fetchCalendars: self.fetchCalendars)
    case .filtering:
        FilteringTab(settings: self.settings)
    case .shortcuts:
        ShortcutsTab(settings: self.settings)
    case .account:
        AccountTab(oauthProvider: self.oauthProvider, onForceSync: self.onForceSync)
    case nil:
        Text("Select a section")
            .foregroundStyle(.secondary)
    }
}
```

**Step 4: Remove the old .frame(width: 500, height: 400) from the TabView body**

The frame is now on the NavigationSplitView. The old line 43 `.frame(width: 500, height: 400)` is gone.

**Step 5: Build and verify**

Run: `make check`
Expected: Clean build, no warnings

**Step 6: Commit**

```bash
git add Sources/GCalNotifier/Settings/PreferencesView.swift
git commit -m "feat: replace TabView with NavigationSplitView sidebar layout"
```

---

### Task 2: Update window size in GCalNotifierApp.swift

**Files:**
- Modify: `Sources/GCalNotifier/GCalNotifierApp.swift:305`

**Step 1: Change window size**

On line 305, change:
```swift
window.setContentSize(NSSize(width: 500, height: 400))
```
to:
```swift
window.setContentSize(NSSize(width: 650, height: 550))
```

**Step 2: Build and verify**

Run: `make check`
Expected: Clean build

**Step 3: Commit**

```bash
git add Sources/GCalNotifier/GCalNotifierApp.swift
git commit -m "feat: increase settings window to 650x550 for sidebar layout"
```

---

### Task 3: Restructure AccountTab to eliminate nested Form/ScrollView

**Files:**
- Modify: `Sources/GCalNotifier/Settings/OAuthSetupView.swift:313-437`

The current `AccountTab` wraps `OAuthSetupView` (which has its own `Form`) inside a `ScrollView` inside a `VStack`. This creates nested forms that render poorly.

**Step 1: Extract OAuthSetupView content into composable sections**

Add a new view to OAuthSetupView.swift that provides the OAuth content WITHOUT a wrapping Form, so AccountTab can compose it into its own Form:

```swift
/// OAuth setup content without a wrapping Form — for embedding in AccountTab's Form.
struct OAuthSetupContent: View {
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var authState: AuthState = .unconfigured
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    private let oauthProvider: GoogleOAuthProvider

    init(oauthProvider: GoogleOAuthProvider = GoogleOAuthProvider()) {
        self.oauthProvider = oauthProvider
    }

    var body: some View {
        Section("Google Calendar Setup") {
            // reuse setupInstructions, credentialsForm, signInStatus, errorView
            // from OAuthSetupView — same content, just no Form wrapper
        }
    }
}
```

The key insight: extract the Section-level content from OAuthSetupView's body into a new `OAuthSetupContent` view that returns `some View` of Section groups (no Form wrapper). Then AccountTab uses this inside its own single Form.

**Step 2: Rewrite AccountTab body**

Replace the AccountTab body with:

```swift
var body: some View {
    Form {
        Section("Google Calendar Setup") {
            setupInstructions
        }

        if !self.authState.canMakeApiCalls {
            Section("OAuth Credentials") {
                credentialsForm
            }
        }

        Section("Connection Status") {
            signInStatus
        }

        if let error = errorMessage {
            Section {
                errorView(error)
            }
        }

        Section("Sync Status") {
            syncStatusSection
        }
    }
    .formStyle(.grouped)
    .task { await self.loadInitialState() }
    .task { await self.pollAuthState() }
}
```

This means AccountTab absorbs OAuthSetupView's properties and logic directly, giving us one flat Form with all sections. The standalone `OAuthSetupView` (used by the first-launch flow) stays unchanged.

**Step 3: Move OAuthSetupView's state and methods into AccountTab**

AccountTab needs these additional properties (merge from OAuthSetupView):
- `@State private var clientId = ""`
- `@State private var clientSecret = ""`
- `@State private var errorMessage: String?`
- `@State private var isSigningIn = false`

And these methods (copy from OAuthSetupView):
- `loadInitialState()`
- `signIn()`
- `signOut()`
- `handleOAuthError(_:)`

And these computed properties (copy from OAuthSetupView):
- `setupInstructions`
- `credentialsForm`
- `signInStatus`
- `statusIndicator`, `statusColor`, `statusText`, `statusTextColor`
- `actionButton`
- `canSignIn`
- `errorView(_:)`
- `instructionStep(number:text:url:)`

Extract the auth-state polling into a method:
```swift
private func pollAuthState() async {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        self.authState = await self.oauthProvider.state
    }
}
```

**Step 4: Build and verify**

Run: `make check`
Expected: Clean build, no warnings

**Step 5: Run tests**

Run: `make test`
Expected: All tests pass

**Step 6: Commit**

```bash
git add Sources/GCalNotifier/Settings/OAuthSetupView.swift
git commit -m "refactor: restructure AccountTab with single Form, eliminate nested Form/ScrollView"
```

---

### Task 4: Visual polish and final verification

**Files:**
- Possibly: `Sources/GCalNotifier/Settings/PreferencesView.swift` (minor tweaks)

**Step 1: Build and run the app**

Run: `make check-test`
Expected: All checks and tests pass

**Step 2: Manual verification checklist**

Open the settings window and verify:
- Sidebar shows all 6 sections with icons
- Clicking each section shows the correct content
- General tab: sliders, toggles all visible without scrolling
- Sounds tab: both sound cards + custom sound visible
- Calendars tab: calendar list loads and scrolls naturally
- Filtering tab: keyword lists with add/remove
- Shortcuts tab: keyboard shortcut recorders
- Account tab: OAuth setup + sync status in one clean Form
- Window is 650x550 and closable
- No content is clipped or hidden without scroll affordance

**Step 3: Commit any polish tweaks**

```bash
git add -A
git commit -m "polish: final settings UI cleanup and adjustments"
```

---

### Task 5: Create bead and push

**Step 1: Close the bead**

```bash
br close gcn-394x --reason "Settings UI redesigned with sidebar navigation"
br sync --flush-only
```

**Step 2: Push**

```bash
git push
```
