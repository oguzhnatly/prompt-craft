import AppKit
import Combine
import Foundation

/// Monitors the system clipboard and maintains an in-memory history of recent text copies.
/// Privacy-first: only runs while PromptCraft is active, nothing is persisted to disk.
final class ClipboardHistoryService: ObservableObject {
    static let shared = ClipboardHistoryService()

    struct ClipboardItem: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let timestamp: Date

        var preview: String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
            if singleLine.count > 60 {
                return String(singleLine.prefix(60)) + "..."
            }
            return singleLine
        }

        var timestampString: String {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: timestamp, relativeTo: Date())
        }
    }

    @Published private(set) var items: [ClipboardItem] = []

    private let maxItems = 20
    private var lastChangeCount: Int = 0
    private var monitorTimer: Timer?
    private var isMonitoring = false
    private let configurationService: ConfigurationService

    private init(configurationService: ConfigurationService = .shared) {
        self.configurationService = configurationService
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Monitoring Control

    /// Start monitoring clipboard changes. Call when the app window/popover becomes visible.
    func startMonitoring() {
        guard !isMonitoring else { return }
        guard configurationService.configuration.clipboardHistoryEnabled else { return }

        isMonitoring = true
        lastChangeCount = NSPasteboard.general.changeCount

        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    /// Stop monitoring clipboard changes. Call when the app window/popover is hidden.
    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        isMonitoring = false
    }

    /// Clear all history items.
    func clearHistory() {
        items.removeAll()
    }

    /// The most recent items for display (up to 10).
    var recentItems: [ClipboardItem] {
        Array(items.prefix(10))
    }

    // MARK: - Private

    private func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Avoid duplicating the most recent item
        if let first = items.first, first.text == text { return }

        let item = ClipboardItem(text: text, timestamp: Date())
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.items.insert(item, at: 0)
            if self.items.count > self.maxItems {
                self.items.removeLast(self.items.count - self.maxItems)
            }
        }
    }
}
