import Combine
import Foundation

final class StyleService: ObservableObject {
    static let shared = StyleService()

    @Published private(set) var styles: [PromptStyle] = []

    /// Set on first load if a style file was corrupted and had to be reset.
    @Published private(set) var didRecoverFromCorruption: Bool = false

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let baseDirectory: URL?

    private convenience init() {
        self.init(baseDirectory: nil)
    }

    init(baseDirectory: URL?) {
        self.baseDirectory = baseDirectory
        loadAll()
    }

    // MARK: - Read

    func getAll() -> [PromptStyle] {
        return styles.filter { !$0.isInternal }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func getEnabled() -> [PromptStyle] {
        return getAll().filter { $0.isEnabled && !$0.isInternal }
    }

    func getById(_ id: UUID) -> PromptStyle? {
        return styles.first { $0.id == id && !$0.isInternal }
    }

    func getByIdIncludingInternal(_ id: UUID) -> PromptStyle? {
        return styles.first { $0.id == id }
    }

    // MARK: - Create

    @discardableResult
    func create(_ style: PromptStyle) -> PromptStyle {
        var newStyle = style
        newStyle.isBuiltIn = false
        newStyle.createdAt = Date()
        newStyle.modifiedAt = Date()
        if newStyle.sortOrder == 0 {
            newStyle.sortOrder = (styles.map(\.sortOrder).max() ?? 0) + 1
        }
        styles.append(newStyle)
        persistAll()
        return newStyle
    }

    // MARK: - Update

    func update(_ style: PromptStyle) {
        guard let index = styles.firstIndex(where: { $0.id == style.id }) else { return }
        var updated = style
        updated.modifiedAt = Date()
        styles[index] = updated
        persistAll()
    }

    // MARK: - Delete

    func delete(_ id: UUID) {
        guard let style = getById(id), !style.isBuiltIn else { return }
        styles.removeAll { $0.id == id }
        persistAll()
    }

    // MARK: - Reorder

    func reorder(_ styleIDs: [UUID]) {
        for (index, id) in styleIDs.enumerated() {
            if let styleIndex = styles.firstIndex(where: { $0.id == id }) {
                styles[styleIndex].sortOrder = index
                styles[styleIndex].modifiedAt = Date()
            }
        }
        persistAll()
    }

    // MARK: - Enable / Disable

    func enable(_ id: UUID) {
        guard let index = styles.firstIndex(where: { $0.id == id }) else { return }
        styles[index].isEnabled = true
        styles[index].modifiedAt = Date()
        persistAll()
    }

    func disable(_ id: UUID) {
        guard let index = styles.firstIndex(where: { $0.id == id }) else { return }
        styles[index].isEnabled = false
        styles[index].modifiedAt = Date()
        persistAll()
    }

    // MARK: - Duplicate

    @discardableResult
    func duplicate(_ id: UUID) -> PromptStyle? {
        guard let original = getById(id) else { return nil }
        let copy = PromptStyle(
            displayName: "\(original.displayName) (Copy)",
            shortDescription: original.shortDescription,
            category: original.category,
            iconName: original.iconName,
            sortOrder: (styles.map(\.sortOrder).max() ?? 0) + 1,
            isBuiltIn: false,
            isEnabled: true,
            systemInstruction: original.systemInstruction,
            outputStructure: original.outputStructure,
            toneDescriptor: original.toneDescriptor,
            fewShotExamples: original.fewShotExamples,
            enforcedPrefix: original.enforcedPrefix,
            enforcedSuffix: original.enforcedSuffix,
            targetModelHint: original.targetModelHint
        )
        styles.append(copy)
        persistAll()
        return copy
    }

    // MARK: - Export / Import

    func exportStyle(_ id: UUID) -> Data? {
        guard let style = getById(id) else { return nil }
        let envelope = StyleExportEnvelope(style: style)
        return try? encoder.encode(envelope)
    }

    func importStyle(from data: Data) -> PromptStyle? {
        // Try envelope format first, then fall back to raw PromptStyle
        let decoded: PromptStyle
        if let envelope = try? decoder.decode(StyleExportEnvelope.self, from: data) {
            decoded = envelope.style
        } else if let raw = try? decoder.decode(PromptStyle.self, from: data) {
            decoded = raw
        } else {
            Logger.shared.warning("Could not decode imported style data")
            return nil
        }

        // Give it a new ID and mark as user-created
        let imported = PromptStyle(
            displayName: decoded.displayName,
            shortDescription: decoded.shortDescription,
            category: decoded.category,
            iconName: decoded.iconName,
            sortOrder: (styles.map(\.sortOrder).max() ?? 0) + 1,
            isBuiltIn: false,
            isEnabled: true,
            systemInstruction: decoded.systemInstruction,
            outputStructure: decoded.outputStructure,
            toneDescriptor: decoded.toneDescriptor,
            fewShotExamples: decoded.fewShotExamples,
            enforcedPrefix: decoded.enforcedPrefix,
            enforcedSuffix: decoded.enforcedSuffix,
            targetModelHint: decoded.targetModelHint
        )
        styles.append(imported)
        persistAll()
        return imported
    }

    /// Dismiss the corruption recovery notice.
    func dismissCorruptionNotice() {
        didRecoverFromCorruption = false
    }

    // MARK: - Private — Persistence

    private var appSupportDirectory: URL {
        if let baseDirectory {
            return baseDirectory
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupport.appendingPathComponent("PromptCraft")
    }

    private var customStylesFileURL: URL {
        return appSupportDirectory.appendingPathComponent("custom-styles.json")
    }

    private var styleOverridesFileURL: URL {
        return appSupportDirectory.appendingPathComponent("style-overrides.json")
    }

    private func ensureDirectoryExists() -> Bool {
        if !fileManager.fileExists(atPath: appSupportDirectory.path) {
            do {
                try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
                return true
            } catch {
                Logger.shared.error("Failed to create app support directory for styles", error: error)
                return false
            }
        }
        return true
    }

    /// Persists built-in overrides (isEnabled, sortOrder) for built-in styles.
    private struct BuiltInOverride: Codable {
        let id: UUID
        var isEnabled: Bool
        var sortOrder: Int
    }

    private func loadAll() {
        // Start with built-in styles (including internal ones like Shorten)
        var allStyles = DefaultStyles.all
        allStyles.append(DefaultStyles.shorten)

        // Apply saved overrides for built-in styles (enable/disable, sort order)
        if fileManager.fileExists(atPath: styleOverridesFileURL.path) {
            do {
                let data = try Data(contentsOf: styleOverridesFileURL)
                let overrides = try decoder.decode([BuiltInOverride].self, from: data)
                let overrideMap = Dictionary(uniqueKeysWithValues: overrides.map { ($0.id, $0) })
                for i in allStyles.indices {
                    if let override = overrideMap[allStyles[i].id] {
                        allStyles[i].isEnabled = override.isEnabled
                        allStyles[i].sortOrder = override.sortOrder
                    }
                }
            } catch {
                Logger.shared.error("Style overrides file corrupted, using defaults", error: error)
                recoverFromCorruption(at: styleOverridesFileURL)
            }
        }

        // Load user-created styles from disk
        if fileManager.fileExists(atPath: customStylesFileURL.path) {
            do {
                let data = try Data(contentsOf: customStylesFileURL)
                let customStyles = try decoder.decode([PromptStyle].self, from: data)
                allStyles.append(contentsOf: customStyles)
            } catch {
                Logger.shared.error("Custom styles file corrupted, recovering", error: error)
                recoverFromCorruption(at: customStylesFileURL)
            }
        }

        styles = allStyles
        Logger.shared.info("Loaded \(styles.count) styles (\(styles.filter { !$0.isBuiltIn }.count) custom)")
    }

    private func recoverFromCorruption(at url: URL) {
        let backupURL = url.deletingPathExtension().appendingPathExtension("bak")
        try? fileManager.removeItem(at: backupURL)
        do {
            try fileManager.moveItem(at: url, to: backupURL)
            Logger.shared.info("Backed up corrupted style file to \(backupURL.lastPathComponent)")
        } catch {
            Logger.shared.error("Could not back up corrupted style file", error: error)
            try? fileManager.removeItem(at: url)
        }
        didRecoverFromCorruption = true
    }

    /// Saves both custom styles and built-in overrides.
    private func persistAll() {
        guard ensureDirectoryExists() else {
            Logger.shared.error("Cannot persist styles: directory creation failed")
            return
        }

        // Save custom styles
        let customStyles = styles.filter { !$0.isBuiltIn }
        do {
            let data = try encoder.encode(customStyles)
            try data.write(to: customStylesFileURL, options: .atomic)
        } catch {
            Logger.shared.error("Failed to persist custom styles", error: error)
        }

        // Save built-in overrides
        let overrides = styles.filter(\.isBuiltIn).map {
            BuiltInOverride(id: $0.id, isEnabled: $0.isEnabled, sortOrder: $0.sortOrder)
        }
        do {
            let data = try encoder.encode(overrides)
            try data.write(to: styleOverridesFileURL, options: .atomic)
        } catch {
            Logger.shared.error("Failed to persist style overrides", error: error)
        }
    }
}
