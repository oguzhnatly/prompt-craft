import Combine
import Foundation

final class HistoryService: ObservableObject {
    static let shared = HistoryService()

    @Published private(set) var entries: [PromptHistoryEntry] = []

    /// Set on first load if the history file was corrupted and had to be reset.
    @Published private(set) var didRecoverFromCorruption: Bool = false

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Maximum history file size before forcing a trim (10 MB).
    private let maxFileSize: UInt64 = 10 * 1024 * 1024
    /// Number of entries to keep when force-trimming.
    private let forceTrimLimit = 200

    private let baseDirectory: URL?
    private let configurationServiceOverride: ConfigurationService?

    private convenience init() {
        self.init(baseDirectory: nil, configurationService: nil)
    }

    init(baseDirectory: URL?, configurationService: ConfigurationService?) {
        self.baseDirectory = baseDirectory
        self.configurationServiceOverride = configurationService
        loadEntries()
    }

    // MARK: - Save

    func save(_ entry: PromptHistoryEntry) {
        entries.insert(entry, at: 0)
        trimIfNeeded()
        persistEntries()
    }

    // MARK: - Read

    func getAll() -> [PromptHistoryEntry] {
        return entries
    }

    func getRecent(_ limit: Int) -> [PromptHistoryEntry] {
        return Array(entries.prefix(limit))
    }

    func getFavorites() -> [PromptHistoryEntry] {
        return entries.filter(\.isFavorited)
    }

    // MARK: - Search

    func search(_ query: String) -> [PromptHistoryEntry] {
        let lowered = query.lowercased()
        return entries.filter {
            $0.inputText.lowercased().contains(lowered)
                || $0.outputText.lowercased().contains(lowered)
        }
    }

    // MARK: - Modify

    func toggleFavorite(_ entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].isFavorited.toggle()
        persistEntries()
    }

    func delete(_ entryID: UUID) {
        entries.removeAll { $0.id == entryID }
        persistEntries()
    }

    func clearAll() {
        entries.removeAll()
        persistEntries()
    }

    /// Dismiss the corruption recovery notice.
    func dismissCorruptionNotice() {
        didRecoverFromCorruption = false
    }

    // MARK: - Private

    private var appSupportDirectory: URL {
        if let baseDirectory {
            return baseDirectory
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupport.appendingPathComponent("PromptCraft")
    }

    private var historyFileURL: URL {
        return appSupportDirectory.appendingPathComponent("history.json")
    }

    private func ensureDirectoryExists() -> Bool {
        if !fileManager.fileExists(atPath: appSupportDirectory.path) {
            do {
                try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
                return true
            } catch {
                Logger.shared.error("Failed to create app support directory", error: error)
                return false
            }
        }
        return true
    }

    private func loadEntries() {
        let path = historyFileURL.path
        guard fileManager.fileExists(atPath: path) else {
            Logger.shared.info("No history file found; starting with empty history")
            return
        }

        do {
            let data = try Data(contentsOf: historyFileURL)
            entries = try decoder.decode([PromptHistoryEntry].self, from: data)
            Logger.shared.info("Loaded \(entries.count) history entries")

            // Check file size and force-trim if needed
            checkFileSizeAndTrim()
        } catch {
            Logger.shared.error("History file corrupted, recovering", error: error)
            recoverFromCorruption(at: historyFileURL)
        }
    }

    private func recoverFromCorruption(at url: URL) {
        // Back up the corrupted file
        let backupURL = url.deletingPathExtension().appendingPathExtension("bak")
        try? fileManager.removeItem(at: backupURL)
        do {
            try fileManager.moveItem(at: url, to: backupURL)
            Logger.shared.info("Backed up corrupted history to \(backupURL.lastPathComponent)")
        } catch {
            Logger.shared.error("Could not back up corrupted history", error: error)
            try? fileManager.removeItem(at: url)
        }

        // Start fresh
        entries = []
        didRecoverFromCorruption = true
    }

    private func persistEntries() {
        guard ensureDirectoryExists() else {
            Logger.shared.error("Cannot persist history: directory creation failed")
            return
        }

        do {
            let data = try encoder.encode(entries)
            try data.write(to: historyFileURL, options: .atomic)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && (error.code == NSFileWriteOutOfSpaceError || error.code == NSFileWriteVolumeReadOnlyError) {
            Logger.shared.error("Disk full or read-only, cannot save history", error: error)
        } catch {
            Logger.shared.error("Failed to persist history", error: error)
        }
    }

    private func trimIfNeeded() {
        let limit = (configurationServiceOverride ?? ConfigurationService.shared).configuration.historyLimit
        if entries.count > limit {
            // Keep favorites even if over limit, trim non-favorites from the end
            let favorites = entries.filter(\.isFavorited)
            var nonFavorites = entries.filter { !$0.isFavorited }
            let maxNonFavorites = max(0, limit - favorites.count)
            nonFavorites = Array(nonFavorites.prefix(maxNonFavorites))

            // Merge and re-sort by timestamp (newest first)
            entries = (favorites + nonFavorites).sorted { $0.timestamp > $1.timestamp }
        }
    }

    private func checkFileSizeAndTrim() {
        do {
            let attrs = try fileManager.attributesOfItem(atPath: historyFileURL.path)
            if let size = attrs[.size] as? UInt64, size > maxFileSize {
                Logger.shared.warning("History file exceeds \(maxFileSize / 1_048_576)MB (\(size) bytes), force-trimming to \(forceTrimLimit) entries")

                let favorites = entries.filter(\.isFavorited)
                var nonFavorites = entries.filter { !$0.isFavorited }
                let maxNonFavorites = max(0, forceTrimLimit - favorites.count)
                nonFavorites = Array(nonFavorites.prefix(maxNonFavorites))
                entries = (favorites + nonFavorites).sorted { $0.timestamp > $1.timestamp }
                persistEntries()
            }
        } catch {
            Logger.shared.warning("Could not check history file size", error: error)
        }
    }

}
