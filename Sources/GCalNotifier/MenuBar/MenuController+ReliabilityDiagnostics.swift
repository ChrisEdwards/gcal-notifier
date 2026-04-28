import AppKit

extension MenuController {
    func createNotificationWarningItem() -> NSMenuItem {
        let title = "Durable alerts degraded"
        let subtitle = "Click to allow notifications or open settings."

        let item = NSMenuItem(
            title: title,
            action: #selector(handleOpenNotificationSettings(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.attributedTitle = self.warningTitle(title: title, subtitle: subtitle, icon: "! ")
        return item
    }

    func createLaunchAtLoginWarningItem(status: LaunchAtLoginStatus) -> NSMenuItem {
        let copy = Self.launchAtLoginWarningCopy(status: status)
        let item = NSMenuItem(
            title: copy.title,
            action: #selector(handleOpenLoginItemsSettings(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.attributedTitle = self.warningTitle(title: copy.title, subtitle: copy.subtitle, icon: "! ")
        return item
    }

    private static func launchAtLoginWarningCopy(status: LaunchAtLoginStatus) -> (title: String, subtitle: String) {
        switch status {
        case .requiresApproval:
            ("Launch at login needs approval", "Approve login item for modal alerts after reboot.")
        case .disabled:
            ("Modal availability degraded", "Enable launch at login for modal alerts after reboot.")
        case let .error(message):
            ("Launch at login unavailable", "Open Login Items settings. \(message)")
        case .enabled:
            ("Launch at login enabled", "Modal alerts are available after login.")
        }
    }

    private func warningTitle(title: String, subtitle: String, icon: String) -> NSAttributedString {
        let warningIcon = NSAttributedString(
            string: icon,
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )
        let titleAttr = NSAttributedString(
            string: title + "\n",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.systemOrange,
            ]
        )
        let subtitleAttr = NSAttributedString(
            string: subtitle,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )

        let fullTitle = NSMutableAttributedString()
        fullTitle.append(warningIcon)
        fullTitle.append(titleAttr)
        fullTitle.append(subtitleAttr)
        return fullTitle
    }
}
