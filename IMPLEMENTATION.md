# Implementation: Development Standards & Practices

This document describes the development standards and practices to adopt from `optimus-clip` and `CodexBar` for this Swift project.

## Table of Contents

1. [Token-Efficient Build System](#1-token-efficient-build-system)
2. [Project Structure](#2-project-structure)
3. [Git Practices](#3-git-practices)
4. [CI/CD Pipeline](#4-cicd-pipeline)
5. [Testing Patterns](#5-testing-patterns)
6. [Error Handling](#6-error-handling)
7. [Configuration Management](#7-configuration-management)
8. [Logging Infrastructure](#8-logging-infrastructure)
9. [Documentation Style](#9-documentation-style)
10. [Release Process](#10-release-process)
11. [Menu Bar App Patterns](#11-menu-bar-app-patterns) *(from CodexBar)*
12. [Agent Guidelines](#12-agent-guidelines) *(from CodexBar)*
13. [Implementation Checklist](#13-implementation-checklist)

---

## 1. Token-Efficient Build System

Reduces token usage in AI agent sessions by ~99% through silent wrappers.

### `hack/run_silent.sh`

Core script providing token-efficient wrappers. Source: [abacus run_silent.sh](https://github.com/steveyegge/abacus/blob/main/hack/run_silent.sh)

| Function | Purpose |
|----------|---------|
| `run_silent(desc, cmd)` | Run command silently, show ✓/✗ status |
| `run_with_quiet(desc, cmd)` | For tools with native quiet flags |
| `run_silent_with_test_count(desc, cmd, type)` | Extract and display test counts |
| `swift_build(desc, config)` | Swift build wrapper |
| `swift_test(desc, parallel)` | Swift test wrapper with count extraction |
| `swift_format(desc, check_only)` | SwiftFormat wrapper |
| `swift_lint(desc, fix, strict)` | SwiftLint wrapper |

**Output Examples:**

```bash
# Default (silent)
$ make build
✓ Build (debug)

$ make test
✓ Unit tests passed (42 tests, 1.234s)

# Verbose mode
$ VERBOSE=1 make build
<full swift build output>
```

### `Makefile`

```makefile
.PHONY: build build-release test test-quiet test-parallel check check-quiet \
        format lint lint-strict check-test all package package-release \
        start stop clean help

# Build targets
build:
	@if [ -n "$$VERBOSE" ]; then \
		swift build; \
	else \
		. ./hack/run_silent.sh && swift_build "Build (debug)" "debug"; \
	fi

build-release:
	@if [ -n "$$VERBOSE" ]; then \
		swift build -c release; \
	else \
		. ./hack/run_silent.sh && swift_build "Build (release)" "release"; \
	fi

# Test targets
test:
	@if [ -n "$$VERBOSE" ]; then \
		swift test; \
	else \
		$(MAKE) test-quiet; \
	fi

test-quiet:
	@. ./hack/run_silent.sh && print_header "Test" "Running unit tests" && \
		swift_test "Unit tests"

test-parallel:
	@if [ -n "$$VERBOSE" ]; then \
		swift test --parallel; \
	else \
		. ./hack/run_silent.sh && print_header "Test" "Running unit tests" && \
			swift_test "Unit tests" "parallel"; \
	fi

# Linting targets
check:
	@if [ -n "$$VERBOSE" ]; then \
		swiftformat . --lint && swiftlint --strict; \
	else \
		$(MAKE) check-quiet; \
	fi

check-quiet:
	@. ./hack/run_silent.sh && print_header "Lint" "Checking code style" && \
		swift_format "SwiftFormat check" "true" && \
		swift_lint "SwiftLint check" "" "strict"

format:
	@if [ -n "$$VERBOSE" ]; then \
		swiftformat .; \
	else \
		. ./hack/run_silent.sh && swift_format "SwiftFormat"; \
	fi

lint:
	@if [ -n "$$VERBOSE" ]; then \
		swiftlint --fix --strict; \
	else \
		. ./hack/run_silent.sh && swift_lint "SwiftLint" "fix" "strict"; \
	fi

lint-strict:
	@if [ -n "$$VERBOSE" ]; then \
		swiftlint --strict; \
	else \
		. ./hack/run_silent.sh && swift_lint "SwiftLint (strict)" "" "strict"; \
	fi

# Combined targets
check-test: check test

all: format lint test

# Packaging targets
package: build
	@./Scripts/package_app.sh

package-release: build-release
	@./Scripts/package_app.sh release

# App control
start:
	@./Scripts/compile_and_run.sh

stop:
	@./Scripts/kill_app.sh

# Cleanup
clean:
	@rm -rf .build *.app
	@echo "Cleaned build artifacts"

help:
	@echo "Available targets:"
	@echo "  build          - Build debug"
	@echo "  build-release  - Build release"
	@echo "  test           - Run tests"
	@echo "  test-parallel  - Run tests in parallel"
	@echo "  check          - Check formatting and linting"
	@echo "  format         - Auto-format code"
	@echo "  lint           - Lint with auto-fix"
	@echo "  lint-strict    - Lint without fixes"
	@echo "  check-test     - Check then test"
	@echo "  all            - Format, lint, test"
	@echo "  package        - Package debug app"
	@echo "  package-release- Package release app"
	@echo "  start          - Build and run app"
	@echo "  stop           - Stop running app"
	@echo "  clean          - Remove build artifacts"
	@echo ""
	@echo "Use VERBOSE=1 for full output"
```

### Token Efficiency Results

| Operation | Verbose Output | Silent Output |
|-----------|---------------|---------------|
| `swift build` | ~50-200 lines | 1 line |
| `swift test` | ~100+ lines | 1 line |
| `swiftlint` | ~20-50 lines | 1 line |
| `swiftformat --lint` | ~10-30 lines | 1 line |

---

## 2. Project Structure

### Two-Target Architecture

Split into Core (testable, no UI dependencies) + Main (UI/system integration):

```
gcal-notifier/
├── Makefile
├── Package.swift
├── version.env
├── .swiftlint.yml
├── .swiftformat
├── .gitignore
├── hack/
│   └── run_silent.sh
├── Scripts/
│   ├── compile_and_run.sh
│   ├── package_app.sh
│   ├── kill_app.sh
│   └── setup_dev_certificate.sh
├── Sources/
│   ├── GCalNotifier/              # Main app (thin UI layer)
│   │   ├── Views/                 # SwiftUI views
│   │   ├── Managers/              # System managers
│   │   ├── Services/              # App-level services
│   │   ├── Environment/           # SwiftUI environment keys
│   │   ├── Extensions/            # Swift extensions
│   │   ├── Settings/              # Settings constants
│   │   ├── Resources/             # Images, strings
│   │   └── GCalNotifierApp.swift  # @main entry point
│   │
│   └── GCalNotifierCore/          # Shared library (testable, no UI)
│       ├── Models/                # Data models
│       ├── Services/              # Business logic services
│       ├── Utilities/             # Helper functions
│       └── Errors/                # Error types
│
├── Tests/
│   └── GCalNotifierTests/         # Unit tests
│
├── docs/
│   └── plans/                     # Design decision documents
│
└── .github/
    └── workflows/
        └── ci.yml
```

### Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GCalNotifier",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "GCalNotifier", targets: ["GCalNotifier"])
    ],
    dependencies: [
        // Hotkey registration
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),

        // MenuBar access from SwiftUI
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.0.0"),
    ],
    targets: [
        // Main executable - thin UI layer
        .executableTarget(
            name: "GCalNotifier",
            dependencies: [
                "GCalNotifierCore",
                "KeyboardShortcuts",
                .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess"),
            ],
            path: "Sources/GCalNotifier",
            resources: [.process("Resources")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("AccessLevelOnImport"),
            ]
        ),

        // Core library - all business logic (zero external deps)
        .target(
            name: "GCalNotifierCore",
            dependencies: [],
            path: "Sources/GCalNotifierCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("AccessLevelOnImport"),
            ]
        ),

        // Tests
        .testTarget(
            name: "GCalNotifierTests",
            dependencies: ["GCalNotifier", "GCalNotifierCore"],
            path: "Tests/GCalNotifierTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("AccessLevelOnImport"),
            ]
        )
    ]
)
```

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Managers | `XxxManager.swift` | `NotificationManager.swift` |
| Services | `XxxService.swift` | `CalendarService.swift` |
| Views | `XxxView.swift` | `SettingsView.swift` |
| Tests | `XxxTests.swift` | `CalendarServiceTests.swift` |
| Protocols | No suffix | `CalendarProvider.swift` |
| Errors | `XxxError.swift` | `CalendarError.swift` |

---

## 3. Git Practices

### `.gitignore`

```gitignore
# Swift Package Manager
.build/
.swiftpm/
Package.resolved

# Xcode
*.xcodeproj/
*.xcworkspace/
xcuserdata/
DerivedData/
*.xcresult

# macOS
.DS_Store
.AppleDouble
.LSOverride

# Build artifacts
*.app/

# Node.js (for build scripts)
node_modules/

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# Secrets
.env
.env.local
*.local

# Test artifacts
coverage/

# Local testing
test
history/
```

### Commit Convention

Follow conventional commits with scope and issue reference:

```
<type>(<scope>): <description> (<issue-id>)

fix(calendar): handle timezone edge case for all-day events (gcn-123)
feat(notifications): add snooze support for reminders (gcn-456)
refactor(core): extract notification scheduling to service (gcn-789)
test(calendar): add coverage for recurring events (gcn-101)
docs(readme): update installation instructions
chore(deps): bump KeyboardShortcuts to 2.1.0
```

**Types:** `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `style`, `perf`

**Scopes:** Match module names (`calendar`, `notifications`, `core`, `ui`, `settings`)

---

## 4. CI/CD Pipeline

### `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  format-check:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Check formatting
        run: swiftformat . --lint

  lint:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Run SwiftLint
        run: swiftlint lint --strict

  build:
    runs-on: macos-15
    strategy:
      matrix:
        config: [debug, release]
    steps:
      - uses: actions/checkout@v4
      - name: Cache SPM
        uses: actions/cache@v4
        with:
          path: .build
          key: ${{ runner.os }}-spm-${{ hashFiles('Package.resolved') }}
          restore-keys: |
            ${{ runner.os }}-spm-
      - name: Build (${{ matrix.config }})
        run: swift build -c ${{ matrix.config }}

  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Cache SPM
        uses: actions/cache@v4
        with:
          path: .build
          key: ${{ runner.os }}-spm-${{ hashFiles('Package.resolved') }}
          restore-keys: |
            ${{ runner.os }}-spm-
      - name: Run tests
        run: swift test --parallel --enable-code-coverage
      - name: Generate coverage report
        run: |
          xcrun llvm-cov export -format="lcov" \
            .build/debug/GCalNotifierPackageTests.xctest/Contents/MacOS/GCalNotifierPackageTests \
            -instr-profile .build/debug/codecov/default.profdata > coverage.lcov
      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          files: coverage.lcov
          fail_ci_if_error: false

  ci-success:
    runs-on: ubuntu-latest
    needs: [format-check, lint, build, test]
    steps:
      - name: All checks passed
        run: echo "All CI checks passed!"
```

---

## 5. Testing Patterns

### Use Apple Testing Framework (not XCTest)

```swift
import Testing
@testable import GCalNotifierCore

@Suite("CalendarService Tests")
struct CalendarServiceTests {

    @Test("fetches events for date range")
    func fetchEventsForDateRange() async throws {
        let service = CalendarService(provider: StubCalendarProvider())
        let events = try await service.fetchEvents(from: .now, to: .now.addingTimeInterval(86400))
        #expect(events.count == 3)
    }

    @Test("throws error when provider fails")
    func throwsOnProviderFailure() async {
        let provider = StubCalendarProvider { throw CalendarError.networkError("timeout") }
        let service = CalendarService(provider: provider)

        await #expect(throws: CalendarError.networkError("timeout")) {
            try await service.fetchEvents(from: .now, to: .now)
        }
    }
}
```

### Test Organization

- One `@Suite` per component
- Descriptive test names explaining the behavior
- Use stubs for external dependencies
- Test error paths as rigorously as happy paths

### Stub Pattern

```swift
struct StubCalendarProvider: CalendarProvider {
    var handler: () async throws -> [CalendarEvent] = { [] }

    func fetchEvents(from: Date, to: Date) async throws -> [CalendarEvent] {
        try await handler()
    }
}
```

---

## 6. Error Handling

### Typed Error Hierarchy

```swift
// Protocol-level errors
public enum CalendarError: Error, Sendable, LocalizedError {
    case networkError(String)
    case authenticationRequired
    case permissionDenied
    case invalidDateRange
    case rateLimited(retryAfter: TimeInterval?)

    public var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationRequired:
            return "Please sign in to your Google account"
        case .permissionDenied:
            return "Calendar access denied. Check System Settings > Privacy"
        case .invalidDateRange:
            return "Invalid date range specified"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Try again in \(Int(seconds)) seconds"
            }
            return "Rate limited. Please wait and try again"
        }
    }

    /// Short message for HUD/toast notifications
    public var shortMessage: String {
        switch self {
        case .networkError: return "Network error"
        case .authenticationRequired: return "Sign in required"
        case .permissionDenied: return "Access denied"
        case .invalidDateRange: return "Invalid dates"
        case .rateLimited: return "Rate limited"
        }
    }
}

// Notification-level errors
public enum NotificationError: Error, Sendable, LocalizedError {
    case permissionDenied
    case schedulingFailed(String)
    case invalidTiming
}
```

### Error Recovery Pattern

```swift
enum ErrorRecoveryManager {
    static func recover(from error: Error) -> RecoveryAction {
        switch error {
        case CalendarError.authenticationRequired:
            return .promptSignIn
        case CalendarError.permissionDenied:
            return .openSystemSettings
        case CalendarError.rateLimited(let retryAfter):
            return .retryAfter(retryAfter ?? 60)
        case CalendarError.networkError:
            return .retryWithBackoff
        default:
            return .showError(error.localizedDescription)
        }
    }
}
```

---

## 7. Configuration Management

### `version.env`

Single source of truth for versioning:

```bash
# Version Configuration
MARKETING_VERSION=0.1.0
BUILD_NUMBER=1
BUNDLE_ID=com.gcal-notifier
```

### `.env.local.template`

Template for secrets (never commit actual `.env.local`):

```bash
# App Store Connect API Key (for notarization)
ASC_KEY_ID=
ASC_ISSUER_ID=
ASC_KEY_BASE64=

# Sparkle ed25519 signing key
SPARKLE_KEY_PATH=

# Developer ID (optional, auto-detected from Keychain)
DEVELOPER_ID=
```

### SettingsKey Pattern

Centralize all UserDefaults keys:

```swift
enum SettingsKey {
    // General
    static let launchAtLogin = "launchAtLogin"
    static let soundEffectsEnabled = "soundEffectsEnabled"

    // Notifications
    static let defaultReminderMinutes = "defaultReminderMinutes"
    static let notificationStyle = "notificationStyle"

    // Calendar
    static let selectedCalendars = "selectedCalendars"
    static let syncIntervalMinutes = "syncIntervalMinutes"
}

enum DefaultSettings {
    static let launchAtLogin = false
    static let soundEffectsEnabled = true
    static let defaultReminderMinutes = 10
    static let syncIntervalMinutes = 15
}

// Usage in SwiftUI
@AppStorage(SettingsKey.launchAtLogin)
private var launchAtLogin = DefaultSettings.launchAtLogin
```

### `.swiftlint.yml`

```yaml
disabled_rules:
  - trailing_whitespace  # SwiftFormat handles this
  - todo                 # Allow TODOs during development
  - identifier_name      # Allow short names in closures

opt_in_rules:
  - unused_declaration
  - unused_import
  - explicit_init
  - explicit_self
  - fatal_error_message
  - first_where
  - force_unwrapping
  - implicitly_unwrapped_optional
  - multiline_parameters
  - overridden_super_call
  - private_outlet
  - redundant_nil_coalescing
  - sorted_first_last
  - yoda_condition

line_length:
  warning: 120
  error: 150
  ignores_comments: true
  ignores_urls: true

file_length:
  warning: 500
  error: 1500

function_body_length:
  warning: 40
  error: 100

type_body_length:
  warning: 310
  error: 500

cyclomatic_complexity:
  warning: 10
  error: 20

force_unwrapping:
  severity: error

force_cast:
  severity: warning

force_try:
  severity: warning

identifier_name:
  min_length:
    warning: 2
    error: 1
  max_length:
    warning: 50
  excluded:
    - i
    - id
    - x
    - y
    - v

included:
  - Sources
  - Tests

excluded:
  - .build
  - .swiftpm
  - Scripts

reporter: xcode
```

### `.swiftformat`

```
--swiftversion 6.0
--indent 4
--tabwidth 4
--smarttabs enabled
--indentcase false
--ifdef indent
--maxwidth 120
--self insert
--selfrequired
--trimwhitespace always
--linebreaks lf
--importgrouping testable-bottom
--elseposition same-line
--guardelse same-line
--allman false
--commas inline
--header strip
--disable wrapMultilineStatementBraces
--exclude .build,.swiftpm,Scripts
```

---

## 8. Logging Infrastructure

Use `OSLog` with subsystem `com.gcal-notifier`. Logs appear in Console.app.

### Usage

```swift
import OSLog

private let logger = Logger(subsystem: "com.gcal-notifier", category: "sync")

// In your code:
logger.info("Sync completed: \(events.count) events")
logger.error("Auth failed: \(error.localizedDescription)")
```

### Categories

Use consistent category names for filtering:

| Category | Usage |
|----------|-------|
| `app` | App lifecycle, startup |
| `sync` | Calendar sync operations |
| `auth` | OAuth authentication |
| `alerts` | Alert scheduling and firing |
| `settings` | Configuration changes |

### Viewing Logs

```bash
# Stream all logs
log stream --predicate 'subsystem contains "com.gcal-notifier"' --level debug

# Filter by category
log stream --predicate 'subsystem contains "com.gcal-notifier" AND category == "sync"'

# Search historical logs
log show --predicate 'subsystem contains "com.gcal-notifier"' --last 1h
```

### Enabling Debug Logs

- `defaults write com.gcal-notifier logLevel debug`
- Or hold Option while clicking "Refresh Now"

No custom log files or rotation needed - Console.app handles this.

---

## 9. Documentation Style

### Documentation Comments

Use `///` with Markdown structure:

```swift
/// Monitors Google Calendar for upcoming events and schedules notifications.
///
/// This service polls the Google Calendar API at configurable intervals
/// and schedules local notifications for events with reminders.
///
/// ## Polling Strategy
/// - **Default interval**: 15 minutes (configurable)
/// - **Smart sync**: More frequent polling when events are imminent
/// - **Battery aware**: Reduces polling when on battery power
///
/// ## Usage
/// ```swift
/// let service = CalendarSyncService()
/// service.delegate = self
/// try await service.startSync()
/// ```
///
/// - Note: Requires calendar permissions. Will prompt user if not granted.
public final class CalendarSyncService {
    // MARK: - Configuration

    /// Polling interval between calendar syncs.
    private let syncInterval: TimeInterval

    // MARK: - State

    /// Delegate receiving sync status updates.
    public weak var delegate: CalendarSyncDelegate?

    // MARK: - Initialization

    /// Creates a new sync service.
    /// - Parameter interval: Sync interval in seconds. Default: 900 (15 min)
    public init(interval: TimeInterval = 900) {
        self.syncInterval = interval
    }

    // MARK: - Lifecycle

    /// Starts background calendar synchronization.
    /// - Throws: `CalendarError.permissionDenied` if calendar access not granted
    public func startSync() async throws {
        // ...
    }

    // MARK: - Private Methods

    private func scheduleNotification(for event: CalendarEvent) {
        // ...
    }
}
```

### MARK Sections

Use consistent ordering:

```swift
// MARK: - Configuration
// MARK: - Dependencies
// MARK: - State
// MARK: - Initialization
// MARK: - Lifecycle
// MARK: - Public Methods
// MARK: - Private Methods
// MARK: - Test Helpers (in test files)
```

---

## 10. Release Process

### Version Bumping

```bash
# Edit version.env
MARKETING_VERSION=0.2.0  # Semantic version
BUILD_NUMBER=2           # Must always increment (Sparkle compares this)
```

### Release Modes

| Mode | Command | Signing | Gatekeeper |
|------|---------|---------|------------|
| Signed | `./Scripts/release.sh` | Developer ID | No warning |
| Unsigned | `./Scripts/release.sh --unsigned` | None | User approval |
| Dry Run | `./Scripts/release.sh --dry-run` | N/A | N/A |

### Release Checklist

Create `RELEASE_CHECKLIST.md`:

```markdown
## Pre-Release Verification

### Code Quality
- [ ] `make check` passes (format + lint)
- [ ] `make test` passes (all tests green)
- [ ] `make build-release` succeeds

### Version
- [ ] `version.env` updated (MARKETING_VERSION + BUILD_NUMBER)
- [ ] CHANGELOG.md updated with release notes
- [ ] BUILD_NUMBER incremented from previous release

### Code Signing (Signed releases only)
- [ ] `codesign --verify --deep --strict GCalNotifier.app` passes
- [ ] `spctl -a -t exec -vvv GCalNotifier.app` shows "Notarized Developer ID"
- [ ] `xcrun stapler validate GCalNotifier.app` confirms ticket attached

### Sparkle (If using auto-updates)
- [ ] ed25519 signature generated for release ZIP
- [ ] appcast.xml updated with new version
- [ ] Download URL returns 200

### GitHub Release
- [ ] Release notes match CHANGELOG
- [ ] Assets uploaded (app ZIP, DMG if applicable)
- [ ] Tag matches MARKETING_VERSION
```

---

## 11. Menu Bar App Patterns *(from CodexBar)*

CodexBar demonstrates sophisticated menu bar app architecture. Adopt these patterns:

### Status Item Controller Modularization

Split large controllers into focused extensions:

```
Sources/GCalNotifier/MenuBar/
├── StatusItemController.swift              # Core state + initialization
├── StatusItemController+Menu.swift         # Menu construction
├── StatusItemController+Actions.swift      # Menu action handlers
├── StatusItemController+Icon.swift         # Icon rendering
└── StatusItemController+Notifications.swift # Badge/alert handling
```

### Dynamic Icon Rendering

```swift
// Sources/GCalNotifier/MenuBar/StatusItemController+Icon.swift

extension StatusItemController {
    /// Renders menu bar icon with optional badge
    func updateIcon(upcomingCount: Int, hasAlert: Bool) {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            // Draw base calendar icon
            self.drawCalendarIcon(in: rect)

            // Draw count badge if events upcoming
            if upcomingCount > 0 {
                self.drawBadge(count: upcomingCount, in: rect)
            }

            // Draw alert indicator if needed
            if hasAlert {
                self.drawAlertDot(in: rect)
            }

            return true
        }
        image.isTemplate = true
        statusItem.button?.image = image
    }

    private func drawCalendarIcon(in rect: NSRect) {
        // Calendar outline
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 2, yRadius: 2)
        NSColor.labelColor.setStroke()
        path.stroke()

        // Calendar header bar
        let headerRect = NSRect(x: rect.minX + 2, y: rect.maxY - 6, width: rect.width - 4, height: 4)
        NSColor.labelColor.setFill()
        NSBezierPath(rect: headerRect).fill()
    }

    private func drawBadge(count: Int, in rect: NSRect) {
        let badgeRect = NSRect(x: rect.maxX - 8, y: rect.minY, width: 8, height: 8)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        // Draw count text
        let text = "\(min(count, 9))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 6, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        let textRect = NSRect(
            x: badgeRect.midX - size.width / 2,
            y: badgeRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        text.draw(in: textRect, withAttributes: attrs)
    }
}
```

### Modern SwiftUI State Management

Use `@Observable` (not `ObservableObject`):

```swift
// Sources/GCalNotifier/ViewModels/CalendarViewModel.swift

import SwiftUI

@Observable
final class CalendarViewModel {
    var events: [CalendarEvent] = []
    var isLoading = false
    var error: CalendarError?

    private let service: CalendarService

    init(service: CalendarService) {
        self.service = service
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            events = try await service.fetchEvents(
                from: .now,
                to: .now.addingTimeInterval(86400 * 7)
            )
            error = nil
        } catch let err as CalendarError {
            error = err
        } catch {
            self.error = .networkError(error.localizedDescription)
        }
    }
}

// In SwiftUI View:
struct EventsView: View {
    @State private var viewModel: CalendarViewModel

    init(service: CalendarService) {
        _viewModel = State(initialValue: CalendarViewModel(service: service))
    }

    var body: some View {
        List(viewModel.events) { event in
            EventRow(event: event)
        }
        .task {
            await viewModel.refresh()
        }
    }
}
```

### NSMenu Dynamic Construction

```swift
// Sources/GCalNotifier/MenuBar/StatusItemController+Menu.swift

extension StatusItemController {
    func rebuildMenu() {
        let menu = NSMenu()

        // Today's events section
        menu.addItem(NSMenuItem.sectionHeader(title: "Today"))
        for event in todayEvents {
            menu.addItem(makeEventMenuItem(event))
        }

        menu.addItem(.separator())

        // Tomorrow's events section
        menu.addItem(NSMenuItem.sectionHeader(title: "Tomorrow"))
        for event in tomorrowEvents {
            menu.addItem(makeEventMenuItem(event))
        }

        menu.addItem(.separator())

        // Actions
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func makeEventMenuItem(_ event: CalendarEvent) -> NSMenuItem {
        let item = NSMenuItem()
        item.title = "\(event.timeString) \(event.title)"
        item.representedObject = event
        item.target = self
        item.action = #selector(eventClicked(_:))

        // Add color indicator
        if let color = event.calendarColor {
            item.image = makeColorDot(color)
        }

        return item
    }
}

extension NSMenuItem {
    static func sectionHeader(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        return item
    }
}
```

---

## 12. Agent Guidelines *(from CodexBar)*

Create `AGENTS.md` for AI/LLM development collaboration:

```markdown
# Agent Guidelines for GCalNotifier

## Build & Run

**Always rebuild after code changes:**
```bash
./Scripts/compile_and_run.sh
```

This kills old instances, builds, tests, packages, and relaunches.

## Code Quality

**Before any handoff:**
```bash
make check  # SwiftFormat lint + SwiftLint
```

## Swift 6 Concurrency

- Use `@Observable` for view models, never `ObservableObject`
- All public types must be `Sendable`
- Use `@MainActor` for UI code
- Prefer `async/await` over completion handlers

## Architecture Rules

1. **Core library has zero UI dependencies**
   - `GCalNotifierCore` must not import AppKit/SwiftUI
   - All business logic goes in Core

2. **Logging**
   - Use `OSLog` with `Logger(subsystem: "com.gcal-notifier", category: "...")`
   - Never log OAuth tokens or API keys

## Menu Bar Patterns

1. **Never block the main thread**
   - All network calls are async
   - Menu construction is fast and cached

2. **Icon updates are batched**
   - Don't update icon on every event change
   - Coalesce updates with debouncing

3. **Menu is rebuilt on demand**
   - Not on every state change
   - Only when menu is about to open

## Testing

1. **Run tests after significant changes:**
   ```bash
   make test
   ```

2. **Test error paths**
   - Every `throws` function needs error case tests
   - Use stubs for external dependencies

## File Organization

- One type per file (exceptions: small related types)
- Extensions in separate files: `Type+Extension.swift`
- Group by feature, not by type

## Commits

Use conventional commits:
```
feat(calendar): add support for recurring events
fix(notifications): correct timezone handling
refactor(core): extract provider protocol
```

## What NOT to Do

- Don't use force unwrapping (`!`) except in tests
- Don't use `try!` or `as!`
- Don't store secrets in UserDefaults (use Keychain)
- Don't poll more frequently than every 60 seconds
- Don't make network calls on app launch (defer until needed)
```

---

## 13. Implementation Checklist

### Phase 1: Foundation *(from optimus-clip)*

- [ ] Create directory structure (`Sources/`, `Tests/`, `Scripts/`, `hack/`, `docs/`)
- [ ] Copy `hack/run_silent.sh` from optimus-clip
- [ ] Create `Makefile` with all targets
- [ ] Create `Package.swift` with two-target architecture
- [ ] Create `.gitignore`
- [ ] Create `version.env`

### Phase 2: Code Quality *(from optimus-clip)*

- [ ] Create `.swiftlint.yml`
- [ ] Create `.swiftformat`
- [ ] Set up CI workflow (`.github/workflows/ci.yml`)
- [ ] Verify `make check` works
- [ ] Verify `make test` works

### Phase 3: Configuration *(from optimus-clip)*

- [ ] Create `SettingsKey` enum for UserDefaults
- [ ] Create typed error enums with `LocalizedError`
- [ ] Set up `os.log` logging infrastructure
- [ ] Create `.env.local.template` for secrets

### Phase 4: Documentation *(from optimus-clip)*

- [ ] Create README with problem/features/quickstart structure
- [ ] Create CLAUDE.md or AGENTS.md for AI agent guidelines
- [ ] Document release process
- [ ] Add inline documentation following style guide

### Phase 5: Release Infrastructure *(from optimus-clip)*

- [ ] Create `Scripts/compile_and_run.sh`
- [ ] Create `Scripts/package_app.sh`
- [ ] Create `Scripts/kill_app.sh`
- [ ] Create release checklist

### Phase 6: Logging

- [ ] Set up `OSLog` with consistent subsystem and categories
- [ ] Add logging to sync, auth, and alert code paths

### Phase 7: Menu Bar Architecture *(from CodexBar)*

- [ ] Create `StatusItemController` with modular extensions
- [ ] Implement dynamic icon rendering with badges
- [ ] Set up NSMenu dynamic construction
- [ ] Use `@Observable` for view models (not `ObservableObject`)

### Phase 8: Polish

- [ ] Create `AGENTS.md` with comprehensive guidelines
- [ ] Add comprehensive tests for Google Calendar integration
- [ ] Performance optimization (menu rebuild, icon updates)
- [ ] Accessibility support
- [ ] Localization support (if needed)
