import Testing
import UserNotifications
@testable import GCalNotifierCore

@Suite("NotificationDelegate Command Tests")
struct NotificationDelegateCommandTests {
    @Test("Stage 1 default activation emits show context command")
    func stage1DefaultActivationEmitsShowContextCommand() async {
        let recorder = AlertCommandRecorder()
        let delegate = NotificationDelegate()
        await delegate.setAlertCommandHandler { command in
            await recorder.record(command)
        }

        await delegate.testHandleResponse(
            alertId: "alert-stage1",
            categoryIdentifier: NotificationScheduler.stage1AlertCategory,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        #expect(await recorder.commands == [.showContext(alertId: "alert-stage1")])
    }

    @Test("Stage 2 Join action emits join command")
    func stage2JoinActionEmitsJoinCommand() async {
        let recorder = AlertCommandRecorder()
        let delegate = NotificationDelegate()
        await delegate.setAlertCommandHandler { command in
            await recorder.record(command)
        }

        await delegate.testHandleResponse(
            alertId: "alert-1",
            categoryIdentifier: NotificationScheduler.stage2AlertCategory,
            actionIdentifier: NotificationScheduler.stage2JoinActionIdentifier
        )

        #expect(await recorder.commands == [.join(alertId: "alert-1")])
    }

    @Test("Stage 2 Dismiss action emits dismiss command")
    func stage2DismissActionEmitsDismissCommand() async {
        let recorder = AlertCommandRecorder()
        let delegate = NotificationDelegate()
        await delegate.setAlertCommandHandler { command in
            await recorder.record(command)
        }

        await delegate.testHandleResponse(
            alertId: "alert-2",
            categoryIdentifier: NotificationScheduler.stage2AlertCategory,
            actionIdentifier: NotificationScheduler.stage2DismissActionIdentifier
        )

        #expect(await recorder.commands == [.dismiss(alertId: "alert-2")])
    }

    @Test("Stage 2 Snooze action emits snooze command")
    func stage2SnoozeActionEmitsSnoozeCommand() async {
        let recorder = AlertCommandRecorder()
        let delegate = NotificationDelegate()
        await delegate.setAlertCommandHandler { command in
            await recorder.record(command)
        }

        await delegate.testHandleResponse(
            alertId: "alert-3",
            categoryIdentifier: NotificationScheduler.stage2AlertCategory,
            actionIdentifier: NotificationScheduler.stage2SnoozeActionIdentifier
        )

        #expect(await recorder.commands == [
            .snooze(alertId: "alert-3", duration: NotificationScheduler.stage2SnoozeDuration),
        ])
    }

    @Test("Stage 2 default activation emits show context command")
    func stage2DefaultActivationEmitsShowContextCommand() async {
        let recorder = AlertCommandRecorder()
        let delegate = NotificationDelegate()
        await delegate.setAlertCommandHandler { command in
            await recorder.record(command)
        }

        await delegate.testHandleResponse(
            alertId: "alert-4",
            categoryIdentifier: NotificationScheduler.stage2AlertCategory,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        #expect(await recorder.commands == [.showContext(alertId: "alert-4")])
    }
}

private actor AlertCommandRecorder {
    private(set) var commands: [AlertCommand] = []

    func record(_ command: AlertCommand) {
        self.commands.append(command)
    }
}
