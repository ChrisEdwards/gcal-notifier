import GCalNotifierCore
import SwiftUI

// MARK: - AlertContentContext

/// Presentation metadata for a single alert content view.
public struct AlertContentContext {
    let stage: AlertStage
    let isSnoozed: Bool
    let snoozeContext: String?
    let contextLine: String?

    public init(
        stage: AlertStage,
        isSnoozed: Bool,
        snoozeContext: String?,
        contextLine: String?
    ) {
        self.stage = stage
        self.isSnoozed = isSnoozed
        self.snoozeContext = snoozeContext
        self.contextLine = contextLine
    }
}

// MARK: - AlertContentView

/// SwiftUI view for single event alert modal content.
/// Displays event details with urgency color coding and action buttons.
public struct AlertContentView: View {
    let event: CalendarEvent
    let stage: AlertStage
    let isSnoozed: Bool
    let snoozeContext: String?
    let contextLine: String?

    let onJoin: () -> Void
    let onSnooze: (TimeInterval) -> Void
    let onOpenCalendar: () -> Void
    let onDismiss: () -> Void
    let snoozeDurations: [TimeInterval]

    public init(
        event: CalendarEvent,
        stage: AlertStage,
        isSnoozed: Bool,
        snoozeContext: String?,
        contextLine: String? = nil,
        onJoin: @escaping () -> Void,
        onSnooze: @escaping (TimeInterval) -> Void,
        onOpenCalendar: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        snoozeDurations: [TimeInterval] = AlertSnoozePolicy.supportedDurations
    ) {
        self.event = event
        self.stage = stage
        self.isSnoozed = isSnoozed
        self.snoozeContext = snoozeContext
        self.contextLine = contextLine
        self.onJoin = onJoin
        self.onSnooze = onSnooze
        self.onOpenCalendar = onOpenCalendar
        self.onDismiss = onDismiss
        self.snoozeDurations = snoozeDurations
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

            Text(self.displayContextLine)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var displayContextLine: String {
        guard let contextLine, !contextLine.isEmpty else { return self.event.contextLine }
        return contextLine
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
            .disabled(self.event.primaryMeetingURL == nil)
            .pointerCursor()

            self.snoozeMenu
                .pointerCursor()

            Button("Open in Cal") {
                self.onOpenCalendar()
            }
            .buttonStyle(.bordered)
            .pointerCursor()

            Spacer()

            Button(action: self.onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .pointerCursor()
        }
    }

    @ViewBuilder
    private var snoozeMenu: some View {
        if self.snoozeDurations.isEmpty {
            Button("Snooze") {}
                .disabled(true)
        } else {
            Menu {
                ForEach(self.snoozeDurations, id: \.self) { duration in
                    Button(self.snoozeLabel(for: duration)) { self.onSnooze(duration) }
                }
            } label: {
                Text("Snooze")
                    .frame(minWidth: 60)
            }
        }
    }

    private func snoozeLabel(for duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
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
        context: AlertContentContext,
        actions: AlertWindowActions
    ) -> some View {
        AlertContentView(
            event: event,
            stage: context.stage,
            isSnoozed: context.isSnoozed,
            snoozeContext: context.snoozeContext,
            contextLine: context.contextLine,
            onJoin: actions.onJoin,
            onSnooze: actions.onSnooze,
            onOpenCalendar: actions.onOpenCalendar,
            onDismiss: actions.onDismiss,
            snoozeDurations: actions.snoozeDurations
        )
    }
}
