import GCalNotifierCore
import SwiftUI

// MARK: - AlertContentView

/// SwiftUI view for single event alert modal content.
/// Displays event details with urgency color coding and action buttons.
public struct AlertContentView: View {
    let event: CalendarEvent
    let stage: AlertStage
    let isSnoozed: Bool
    let snoozeContext: String?

    let onJoin: () -> Void
    let onSnooze: (TimeInterval) -> Void
    let onOpenCalendar: () -> Void
    let onDismiss: () -> Void

    public init(
        event: CalendarEvent,
        stage: AlertStage,
        isSnoozed: Bool,
        snoozeContext: String?,
        onJoin: @escaping () -> Void,
        onSnooze: @escaping (TimeInterval) -> Void,
        onOpenCalendar: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.event = event
        self.stage = stage
        self.isSnoozed = isSnoozed
        self.snoozeContext = snoozeContext
        self.onJoin = onJoin
        self.onSnooze = onSnooze
        self.onOpenCalendar = onOpenCalendar
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            eventDetails
            actions
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - Header

extension AlertContentView {
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(self.headerText)
                .font(.headline)
                .foregroundColor(self.headerColor)

            if self.isSnoozed, let context = snoozeContext {
                Text(context)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var headerText: String {
        let timeUntil = self.event.startTime.timeIntervalSinceNow

        if timeUntil <= 0 {
            return "Meeting started!"
        } else if timeUntil < 60 {
            return "Meeting starts now"
        } else {
            let minutes = Int(timeUntil / 60)
            return "Meeting in \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
    }

    private var headerColor: Color {
        let timeUntil = self.event.startTime.timeIntervalSinceNow
        if timeUntil <= 60 {
            return .red
        } else if timeUntil <= 5 * 60 {
            return .orange
        } else {
            return .primary
        }
    }
}

// MARK: - Event Details

extension AlertContentView {
    private var eventDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(self.event.title)
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(2)

            Text(self.timeRange)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(self.event.contextLine)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        let start = formatter.string(from: self.event.startTime)
        let end = formatter.string(from: self.event.endTime)

        return "\(start) - \(end)"
    }
}

// MARK: - Actions

extension AlertContentView {
    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: self.onJoin) {
                Text("Join")
                    .frame(minWidth: 60)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(self.event.primaryMeetingURL == nil)

            self.snoozeMenu

            Button("Open in Cal") {
                self.onOpenCalendar()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(action: self.onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var snoozeMenu: some View {
        Menu {
            Button("1 minute") { self.onSnooze(60) }
            Button("3 minutes") { self.onSnooze(180) }
            Button("5 minutes") { self.onSnooze(300) }
        } label: {
            Text("Snooze")
                .frame(minWidth: 60)
        }
    }
}

// MARK: - CombinedAlertContentView

/// SwiftUI view for displaying multiple conflicting events in a single alert.
public struct CombinedAlertContentView: View {
    let events: [CalendarEvent]
    let onJoin: (CalendarEvent) -> Void
    let onDismissAll: () -> Void

    public init(
        events: [CalendarEvent],
        onJoin: @escaping (CalendarEvent) -> Void,
        onDismissAll: @escaping () -> Void
    ) {
        self.events = events
        self.onJoin = onJoin
        self.onDismissAll = onDismissAll
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.headerSection
            self.eventList
            self.actionButtons
        }
        .padding(20)
        .frame(width: 450)
    }

    private var headerSection: some View {
        Text("\(self.events.count) meetings starting soon")
            .font(.headline)
    }

    private var eventList: some View {
        ForEach(self.events) { event in
            HStack {
                Text("▶")
                    .foregroundColor(.blue)
                Text(event.title)
                    .lineLimit(1)
                Spacer()
                Text(self.formatTime(event.startTime))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            ForEach(self.events) { event in
                Button("Join \(self.shortTitle(event))") {
                    self.onJoin(event)
                }
                .buttonStyle(.bordered)
                .disabled(event.primaryMeetingURL == nil)
            }

            Spacer()

            Button("Dismiss All") {
                self.onDismissAll()
            }
            .buttonStyle(.borderless)
        }
    }

    private func shortTitle(_ event: CalendarEvent) -> String {
        if event.title.count > 15 {
            return String(event.title.prefix(12)) + "..."
        }
        return event.title
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - AlertContentProvider Implementation

/// Content provider that creates AlertContentView instances.
public struct AlertContentViewProvider: AlertContentProvider {
    public init() {}

    public func makeContentView(
        event: CalendarEvent,
        stage: AlertStage,
        isSnoozed: Bool,
        snoozeContext: String?,
        actions: AlertWindowActions
    ) -> some View {
        AlertContentView(
            event: event,
            stage: stage,
            isSnoozed: isSnoozed,
            snoozeContext: snoozeContext,
            onJoin: actions.onJoin,
            onSnooze: actions.onSnooze,
            onOpenCalendar: actions.onOpenCalendar,
            onDismiss: actions.onDismiss
        )
    }
}
