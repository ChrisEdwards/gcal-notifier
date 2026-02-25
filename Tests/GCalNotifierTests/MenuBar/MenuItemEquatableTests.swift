import Testing
@testable import GCalNotifier

// MARK: - MenuItem Equatable Tests

@Suite("MenuItem Equatable Tests")
struct MenuItemEquatableTests {
    @Test("Notification warning items are equal")
    func notificationWarningsAreEqual() {
        #expect(MenuBuilder.MenuItem.notificationWarning == MenuBuilder.MenuItem.notificationWarning)
    }

    @Test("Separator items are equal")
    func separatorsAreEqual() {
        #expect(MenuBuilder.MenuItem.separator == MenuBuilder.MenuItem.separator)
    }

    @Test("Action items with same values are equal")
    func actionItemsEqual() {
        let item1 = MenuBuilder.MenuItem.action(title: "Refresh", action: .refresh)
        let item2 = MenuBuilder.MenuItem.action(title: "Refresh", action: .refresh)
        #expect(item1 == item2)
    }

    @Test("Action items with different actions are not equal")
    func actionItemsNotEqual() {
        let item1 = MenuBuilder.MenuItem.action(title: "Refresh", action: .refresh)
        let item2 = MenuBuilder.MenuItem.action(title: "Refresh", action: .settings)
        #expect(item1 != item2)
    }

    @Test("Empty state items with same message are equal")
    func emptyStateItemsEqual() {
        let item1 = MenuBuilder.MenuItem.emptyState(message: "No meetings")
        let item2 = MenuBuilder.MenuItem.emptyState(message: "No meetings")
        #expect(item1 == item2)
    }

    @Test("OpenNotificationSettings action items are equal")
    func openNotificationSettingsActionItemsEqual() {
        let item1 = MenuBuilder.MenuItem.action(title: "Open Settings", action: .openNotificationSettings)
        let item2 = MenuBuilder.MenuItem.action(title: "Open Settings", action: .openNotificationSettings)
        #expect(item1 == item2)
    }
}
