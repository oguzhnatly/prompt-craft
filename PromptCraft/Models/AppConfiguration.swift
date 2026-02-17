import AppKit
import Foundation

// MARK: - Supporting Enums

enum LLMProvider: String, Codable, CaseIterable {
    case anthropicClaude
    case openAI
    case ollama
    case custom
    case promptCraftCloud

    var displayName: String {
        switch self {
        case .anthropicClaude: return "Anthropic Claude"
        case .openAI: return "OpenAI"
        case .ollama: return "Ollama"
        case .custom: return "Custom"
        case .promptCraftCloud: return "PromptCraft Cloud"
        }
    }

    var defaultModelName: String {
        switch self {
        case .anthropicClaude: return "claude-sonnet-4-5-20250929"
        case .openAI: return "gpt-4o"
        case .ollama: return "qwen3"
        case .custom: return ""
        case .promptCraftCloud: return "pc-standard"
        }
    }
}

// MARK: - License & Trial Enums

enum LicenseType: String, Codable, Equatable {
    case pro
    case cloud
}

enum TrialState: Equatable {
    case active(daysRemaining: Int)
    case expired
    case pro
    case cloud
}

enum ThemePreference: String, Codable, CaseIterable {
    case system
    case light
    case dark
}

extension ThemePreference {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum ExportFormat: String, Codable, CaseIterable {
    case plainText
    case markdown
    case claude
    case chatGPT
    case githubIssue

    var displayName: String {
        switch self {
        case .plainText: return "Plain Text"
        case .markdown: return "Markdown"
        case .claude: return "Claude (XML)"
        case .chatGPT: return "ChatGPT"
        case .githubIssue: return "GitHub Issue"
        }
    }

    var menuLabel: String {
        switch self {
        case .plainText: return "Copy as Plain Text"
        case .markdown: return "Copy as Markdown"
        case .claude: return "Copy for Claude"
        case .chatGPT: return "Copy for ChatGPT"
        case .githubIssue: return "Copy for GitHub Issue"
        }
    }

    var iconName: String {
        switch self {
        case .plainText: return "doc.plaintext"
        case .markdown: return "text.badge.checkmark"
        case .claude: return "chevron.left.forwardslash.chevron.right"
        case .chatGPT: return "bubble.left.and.text.bubble.right"
        case .githubIssue: return "arrow.triangle.branch"
        }
    }
}

enum OutputVerbosity: String, Codable, CaseIterable {
    case concise
    case balanced
    case detailed

    var displayName: String {
        switch self {
        case .concise: return "Concise"
        case .balanced: return "Balanced"
        case .detailed: return "Detailed"
        }
    }

    var descriptionText: String {
        switch self {
        case .concise: return "Enforces strict word limits. Best for simple prompts."
        case .balanced: return "Relaxes tier by one level. Allows slightly longer output."
        case .detailed: return "Always uses full structured formatting."
        }
    }

    var badgeSymbol: String {
        switch self {
        case .concise: return "C"
        case .balanced: return "B"
        case .detailed: return "D"
        }
    }
}

enum AppMode: String, Codable, CaseIterable, Equatable {
    case menubarOnly
    case desktopWindow
    case both

    var displayName: String {
        switch self {
        case .menubarOnly: return "Menubar"
        case .desktopWindow: return "Desktop"
        case .both: return "Both"
        }
    }
}

struct KeyboardShortcutDefinition: Codable, Equatable {
    var keyEquivalent: String
    var commandModifier: Bool
    var shiftModifier: Bool
    var optionModifier: Bool
    var controlModifier: Bool

    static let `default` = KeyboardShortcutDefinition(
        keyEquivalent: "p",
        commandModifier: true,
        shiftModifier: true,
        optionModifier: false,
        controlModifier: false
    )

    /// Convert to NSEvent.ModifierFlags for event matching.
    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if commandModifier { flags.insert(.command) }
        if shiftModifier { flags.insert(.shift) }
        if optionModifier { flags.insert(.option) }
        if controlModifier { flags.insert(.control) }
        return flags
    }

    /// Human-readable display string (e.g., "⌘⇧P").
    var displayString: String {
        var parts: [String] = []
        if controlModifier { parts.append("\u{2303}") }
        if optionModifier { parts.append("\u{2325}") }
        if shiftModifier { parts.append("\u{21E7}") }
        if commandModifier { parts.append("\u{2318}") }
        parts.append(keyEquivalent.uppercased())
        return parts.joined()
    }

    /// Check if an NSEvent matches this shortcut definition.
    func matches(_ event: NSEvent) -> Bool {
        let targetMods: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let eventMods = event.modifierFlags.intersection(targetMods)
        return eventMods == modifierFlags
            && event.charactersIgnoringModifiers?.lowercased() == keyEquivalent.lowercased()
    }
}

// MARK: - AppConfiguration

struct AppConfiguration: Codable, Equatable {
    var selectedProvider: LLMProvider
    var selectedModelName: String
    var temperature: Double
    var maxOutputTokens: Int
    var globalShortcut: KeyboardShortcutDefinition
    var autoCopyToClipboard: Bool
    var showDiffView: Bool
    var themePreference: ThemePreference
    var enabledStyleIDs: [UUID]
    var playSoundOnComplete: Bool
    var showCharacterCount: Bool
    var launchAtLogin: Bool
    var analyticsOptIn: Bool
    var historyLimit: Int

    // Clipboard & shortcut settings
    var clipboardCaptureEnabled: Bool
    var autoCaptureSelectedText: Bool
    var quickOptimizeEnabled: Bool
    var quickOptimizeAutoClose: Bool
    var quickOptimizeAutoCloseDelay: Double

    // Context Engine settings
    var contextEngineEnabled: Bool
    var contextRelevanceThreshold: Float
    var contextMaxEntries: Int

    // Inline Overlay settings
    var inlineOverlayEnabled: Bool
    var inlineOverlayDelayMs: Int
    var overlayExcludedApps: [String]
    var lastUsedStyleID: UUID?

    // Desktop window mode settings
    var appMode: AppMode
    var showDockIcon: Bool

    // Clipboard history
    var clipboardHistoryEnabled: Bool

    // Export format
    var defaultExportFormat: ExportFormat

    // Output verbosity
    var outputVerbosity: OutputVerbosity

    // Ollama
    var ollamaPort: Int

    // Watch Folder
    var watchFolderEnabled: Bool
    var watchFolderPath: String
    var watchFolderAutoClipboard: Bool
    var watchFolderStyleID: UUID?

    static let `default` = AppConfiguration(
        selectedProvider: .anthropicClaude,
        selectedModelName: LLMProvider.anthropicClaude.defaultModelName,
        temperature: 0.3,
        maxOutputTokens: 2048,
        globalShortcut: .default,
        autoCopyToClipboard: true,
        showDiffView: false,
        themePreference: .system,
        enabledStyleIDs: DefaultStyles.all.map(\.id),
        playSoundOnComplete: false,
        showCharacterCount: true,
        launchAtLogin: false,
        analyticsOptIn: false,
        historyLimit: 500,
        clipboardCaptureEnabled: true,
        autoCaptureSelectedText: false,
        quickOptimizeEnabled: false,
        quickOptimizeAutoClose: false,
        quickOptimizeAutoCloseDelay: 2.5,
        contextEngineEnabled: true,
        contextRelevanceThreshold: 0.65,
        contextMaxEntries: 1000,
        inlineOverlayEnabled: true,
        inlineOverlayDelayMs: 500,
        overlayExcludedApps: [],
        lastUsedStyleID: nil,
        appMode: .menubarOnly,
        showDockIcon: true,
        clipboardHistoryEnabled: true,
        defaultExportFormat: .plainText,
        outputVerbosity: .concise,
        ollamaPort: 11434,
        watchFolderEnabled: false,
        watchFolderPath: "~/PromptCraft/inbox/",
        watchFolderAutoClipboard: true,
        watchFolderStyleID: nil
    )

    // Support decoding configs saved before new fields were added.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedProvider = (try? container.decode(LLMProvider.self, forKey: .selectedProvider)) ?? .anthropicClaude
        selectedModelName = try container.decode(String.self, forKey: .selectedModelName)
        temperature = try container.decode(Double.self, forKey: .temperature)
        maxOutputTokens = try container.decode(Int.self, forKey: .maxOutputTokens)
        globalShortcut = try container.decode(KeyboardShortcutDefinition.self, forKey: .globalShortcut)
        autoCopyToClipboard = try container.decode(Bool.self, forKey: .autoCopyToClipboard)
        showDiffView = try container.decode(Bool.self, forKey: .showDiffView)
        themePreference = try container.decode(ThemePreference.self, forKey: .themePreference)
        enabledStyleIDs = try container.decode([UUID].self, forKey: .enabledStyleIDs)
        playSoundOnComplete = try container.decode(Bool.self, forKey: .playSoundOnComplete)
        showCharacterCount = try container.decodeIfPresent(Bool.self, forKey: .showCharacterCount) ?? true
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        analyticsOptIn = try container.decode(Bool.self, forKey: .analyticsOptIn)
        historyLimit = try container.decode(Int.self, forKey: .historyLimit)
        clipboardCaptureEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardCaptureEnabled) ?? true
        autoCaptureSelectedText = try container.decodeIfPresent(Bool.self, forKey: .autoCaptureSelectedText) ?? false
        quickOptimizeEnabled = try container.decodeIfPresent(Bool.self, forKey: .quickOptimizeEnabled) ?? false
        quickOptimizeAutoClose = try container.decodeIfPresent(Bool.self, forKey: .quickOptimizeAutoClose) ?? false
        quickOptimizeAutoCloseDelay = try container.decodeIfPresent(Double.self, forKey: .quickOptimizeAutoCloseDelay) ?? 2.5
        contextEngineEnabled = try container.decodeIfPresent(Bool.self, forKey: .contextEngineEnabled) ?? true
        contextRelevanceThreshold = try container.decodeIfPresent(Float.self, forKey: .contextRelevanceThreshold) ?? 0.65
        contextMaxEntries = try container.decodeIfPresent(Int.self, forKey: .contextMaxEntries) ?? 1000
        inlineOverlayEnabled = try container.decodeIfPresent(Bool.self, forKey: .inlineOverlayEnabled) ?? true
        inlineOverlayDelayMs = try container.decodeIfPresent(Int.self, forKey: .inlineOverlayDelayMs) ?? 500
        overlayExcludedApps = try container.decodeIfPresent([String].self, forKey: .overlayExcludedApps) ?? []
        lastUsedStyleID = try container.decodeIfPresent(UUID.self, forKey: .lastUsedStyleID)
        appMode = try container.decodeIfPresent(AppMode.self, forKey: .appMode) ?? .menubarOnly
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? true
        clipboardHistoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardHistoryEnabled) ?? true
        defaultExportFormat = try container.decodeIfPresent(ExportFormat.self, forKey: .defaultExportFormat) ?? .plainText
        outputVerbosity = try container.decodeIfPresent(OutputVerbosity.self, forKey: .outputVerbosity) ?? .concise
        ollamaPort = try container.decodeIfPresent(Int.self, forKey: .ollamaPort) ?? 11434
        watchFolderEnabled = try container.decodeIfPresent(Bool.self, forKey: .watchFolderEnabled) ?? false
        watchFolderPath = try container.decodeIfPresent(String.self, forKey: .watchFolderPath) ?? "~/PromptCraft/inbox/"
        watchFolderAutoClipboard = try container.decodeIfPresent(Bool.self, forKey: .watchFolderAutoClipboard) ?? true
        watchFolderStyleID = try container.decodeIfPresent(UUID.self, forKey: .watchFolderStyleID)
    }

    init(
        selectedProvider: LLMProvider,
        selectedModelName: String,
        temperature: Double,
        maxOutputTokens: Int,
        globalShortcut: KeyboardShortcutDefinition,
        autoCopyToClipboard: Bool,
        showDiffView: Bool,
        themePreference: ThemePreference,
        enabledStyleIDs: [UUID],
        playSoundOnComplete: Bool,
        showCharacterCount: Bool = true,
        launchAtLogin: Bool,
        analyticsOptIn: Bool,
        historyLimit: Int,
        clipboardCaptureEnabled: Bool = true,
        autoCaptureSelectedText: Bool = false,
        quickOptimizeEnabled: Bool = false,
        quickOptimizeAutoClose: Bool = false,
        quickOptimizeAutoCloseDelay: Double = 2.5,
        contextEngineEnabled: Bool = true,
        contextRelevanceThreshold: Float = 0.65,
        contextMaxEntries: Int = 1000,
        inlineOverlayEnabled: Bool = true,
        inlineOverlayDelayMs: Int = 500,
        overlayExcludedApps: [String] = [],
        lastUsedStyleID: UUID? = nil,
        appMode: AppMode = .menubarOnly,
        showDockIcon: Bool = true,
        clipboardHistoryEnabled: Bool = true,
        defaultExportFormat: ExportFormat = .plainText,
        outputVerbosity: OutputVerbosity = .concise,
        ollamaPort: Int = 11434,
        watchFolderEnabled: Bool = false,
        watchFolderPath: String = "~/PromptCraft/inbox/",
        watchFolderAutoClipboard: Bool = true,
        watchFolderStyleID: UUID? = nil
    ) {
        self.selectedProvider = selectedProvider
        self.selectedModelName = selectedModelName
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.globalShortcut = globalShortcut
        self.autoCopyToClipboard = autoCopyToClipboard
        self.showDiffView = showDiffView
        self.themePreference = themePreference
        self.enabledStyleIDs = enabledStyleIDs
        self.playSoundOnComplete = playSoundOnComplete
        self.showCharacterCount = showCharacterCount
        self.launchAtLogin = launchAtLogin
        self.analyticsOptIn = analyticsOptIn
        self.historyLimit = historyLimit
        self.clipboardCaptureEnabled = clipboardCaptureEnabled
        self.autoCaptureSelectedText = autoCaptureSelectedText
        self.quickOptimizeEnabled = quickOptimizeEnabled
        self.quickOptimizeAutoClose = quickOptimizeAutoClose
        self.quickOptimizeAutoCloseDelay = quickOptimizeAutoCloseDelay
        self.contextEngineEnabled = contextEngineEnabled
        self.contextRelevanceThreshold = contextRelevanceThreshold
        self.contextMaxEntries = contextMaxEntries
        self.inlineOverlayEnabled = inlineOverlayEnabled
        self.inlineOverlayDelayMs = inlineOverlayDelayMs
        self.overlayExcludedApps = overlayExcludedApps
        self.lastUsedStyleID = lastUsedStyleID
        self.appMode = appMode
        self.showDockIcon = showDockIcon
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
        self.defaultExportFormat = defaultExportFormat
        self.outputVerbosity = outputVerbosity
        self.ollamaPort = ollamaPort
        self.watchFolderEnabled = watchFolderEnabled
        self.watchFolderPath = watchFolderPath
        self.watchFolderAutoClipboard = watchFolderAutoClipboard
        self.watchFolderStyleID = watchFolderStyleID
    }
}
