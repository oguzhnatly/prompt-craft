import AppKit
import Sparkle

final class ContextMenuService {
    static let shared = ContextMenuService()

    private let styleService = StyleService.shared
    private let historyService = HistoryService.shared
    private let menuOptimizationService = MenuOptimizationService.shared
    private let clipboardService = ClipboardService.shared

    private init() {}

    // MARK: - Build Menu

    func buildMenu(updater: SPUUpdater?) -> NSMenu {
        let menu = NSMenu()

        // Quick Optimize Clipboard
        let quickItem = NSMenuItem(
            title: "Quick Optimize Clipboard",
            action: #selector(handleQuickOptimize(_:)),
            keyEquivalent: ""
        )
        quickItem.target = self
        menu.addItem(quickItem)

        // Optimize with... submenu
        let optimizeSubmenu = NSMenu()
        for style in styleService.getEnabled() {
            let item = NSMenuItem(
                title: style.displayName,
                action: #selector(handleOptimizeWithStyle(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = style.id
            optimizeSubmenu.addItem(item)
        }
        let optimizeItem = NSMenuItem(title: "Optimize with...", action: nil, keyEquivalent: "")
        optimizeItem.submenu = optimizeSubmenu
        menu.addItem(optimizeItem)

        // Shorten Clipboard
        let shortenItem = NSMenuItem(
            title: "Shorten Clipboard",
            action: #selector(handleShortenClipboard(_:)),
            keyEquivalent: ""
        )
        shortenItem.target = self
        menu.addItem(shortenItem)

        menu.addItem(.separator())

        // Recent submenu
        let recentEntries = historyService.getRecent(5)
        if !recentEntries.isEmpty {
            let recentSubmenu = NSMenu()
            for entry in recentEntries {
                let preview = truncateForMenu(entry.outputText)
                let item = NSMenuItem(
                    title: preview,
                    action: #selector(handleCopyRecent(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = entry.outputText
                recentSubmenu.addItem(item)
            }
            let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            recentItem.submenu = recentSubmenu
            menu.addItem(recentItem)

            menu.addItem(.separator())
        }

        // Desktop window
        let desktopItem = NSMenuItem(
            title: "Open Desktop Window",
            action: #selector(handleOpenDesktopWindow(_:)),
            keyEquivalent: ""
        )
        desktopItem.target = self
        menu.addItem(desktopItem)

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(handleOpenSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Check for Updates
        if let updater {
            let updateItem = NSMenuItem(
                title: "Check for Updates...",
                action: #selector(SPUUpdater.checkForUpdates),
                keyEquivalent: ""
            )
            updateItem.target = updater
            menu.addItem(updateItem)
        }

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit PromptCraft",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Actions

    @objc private func handleQuickOptimize(_ sender: NSMenuItem) {
        menuOptimizationService.quickOptimizeClipboard()
    }

    @objc private func handleOptimizeWithStyle(_ sender: NSMenuItem) {
        guard let styleID = sender.representedObject as? UUID else { return }
        menuOptimizationService.optimizeClipboard(with: styleID)
    }

    @objc private func handleShortenClipboard(_ sender: NSMenuItem) {
        menuOptimizationService.optimizeClipboard(with: DefaultStyles.shorten.id)
    }

    @objc private func handleCopyRecent(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        clipboardService.writeText(text)
    }

    @objc private func handleOpenDesktopWindow(_ sender: NSMenuItem) {
        NotificationCenter.default.post(
            name: AppConstants.Notifications.openDesktopWindow,
            object: nil
        )
    }

    @objc private func handleOpenSettings(_ sender: NSMenuItem) {
        NotificationCenter.default.post(
            name: AppConstants.Notifications.navigateToSettings,
            object: nil
        )
    }

    // MARK: - Helpers

    private func truncateForMenu(_ text: String) -> String {
        let singleLine = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if singleLine.count > 60 {
            return String(singleLine.prefix(60)) + "..."
        }
        return singleLine
    }
}
