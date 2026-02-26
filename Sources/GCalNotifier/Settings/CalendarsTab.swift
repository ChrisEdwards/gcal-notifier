import GCalNotifierCore
import SwiftUI

// MARK: - Calendars Tab

/// Calendar selection for which calendars to monitor, shown as a live checkbox list.
struct CalendarsTab: View {
    @Bindable var settings: SettingsStore
    let fetchCalendars: (() async throws -> [CalendarInfo])?

    @State private var isLoading = false
    @State private var fetchFailed = false

    private var displayedCalendars: [CalendarInfo] {
        self.settings.cachedCalendarList.sorted {
            if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
            return $0.summary < $1.summary
        }
    }

    private var checkedCount: Int {
        if self.settings.enabledCalendars.isEmpty { return self.displayedCalendars.count }
        return self.displayedCalendars.count(where: { self.settings.enabledCalendars.contains($0.id) })
    }

    var body: some View {
        Form {
            Section {
                Text("Select which calendars should trigger meeting alerts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Calendars") {
                if self.displayedCalendars.isEmpty, self.isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading calendars…").foregroundStyle(.secondary)
                    }
                } else if self.displayedCalendars.isEmpty, self.fetchFailed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Could not load calendars.")
                            .foregroundStyle(.secondary)
                        Button("Retry") { Task { await self.refresh() } }
                    }
                } else {
                    ForEach(self.displayedCalendars) { calendar in
                        let binding = self.isEnabled(calendar)
                        Toggle(isOn: binding) {
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
                        .disabled(self.checkedCount == 1 && binding.wrappedValue)
                        .help(self.checkedCount == 1 && binding.wrappedValue
                            ? "At least one calendar must be selected."
                            : "")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await self.refresh() }
    }

    private func isEnabled(_ calendar: CalendarInfo) -> Binding<Bool> {
        Binding(
            get: {
                self.settings.enabledCalendars.isEmpty
                    || self.settings.enabledCalendars.contains(calendar.id)
            },
            set: { checked in
                if checked {
                    var enabled = self.settings.enabledCalendars
                    if !enabled.contains(calendar.id) { enabled.append(calendar.id) }
                    let allIds = Set(self.displayedCalendars.map(\.id))
                    self.settings.enabledCalendars = Set(enabled).isSuperset(of: allIds) ? [] : enabled
                } else {
                    var enabled = self.settings.enabledCalendars.isEmpty
                        ? self.displayedCalendars.map(\.id)
                        : self.settings.enabledCalendars
                    enabled.removeAll { $0 == calendar.id }
                    self.settings.enabledCalendars = enabled
                }
            }
        )
    }

    private func refresh() async {
        guard let fetch = self.fetchCalendars else { return }
        self.isLoading = true
        defer { self.isLoading = false }
        do {
            let calendars = try await fetch()
            self.settings.cachedCalendarList = calendars
            if !self.settings.enabledCalendars.isEmpty {
                let validIds = Set(calendars.map(\.id))
                self.settings.enabledCalendars = self.settings.enabledCalendars.filter {
                    validIds.contains($0)
                }
            }
            self.fetchFailed = false
        } catch {
            if self.settings.cachedCalendarList.isEmpty { self.fetchFailed = true }
        }
    }
}
