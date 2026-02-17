import AppKit
import Combine
import SwiftUI

final class MainViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var outputText: String = ""
    @Published var outputVerbosityUsed: OutputVerbosity?
    @Published var selectedStyle: PromptStyle?
    @Published var isProcessing: Bool = false
    @Published var availableStyles: [PromptStyle] = []
    @Published var selectedStyleDescription: String = ""
    @Published var errorMessage: String?
    @Published var wasCancelled: Bool = false

    // Clipboard integration
    @Published var inputTruncationWarning: String?
    @Published var clipboardCopiedNotification: Bool = false
    @Published var isOutputOnClipboard: Bool = false

    // Error action: if true, the current error suggests opening Settings.
    @Published var errorSuggestsSettings: Bool = false

    // Long input confirmation
    @Published var showLongInputWarning: Bool = false
    @Published var longInputCharCount: Int = 0

    // Partial response handling
    @Published var isPartialResponse: Bool = false

    // Context engine state
    @Published var contextUsed: Bool = false
    @Published var contextEntryCount: Int = 0

    // Complexity classification
    @Published var detectedComplexityTier: ComplexityTier = .trivial
    @Published var complexityContextBoosted: Bool = false

    // Calibration enforcement
    @Published var detectedMaxOutputWords: Int = 0
    @Published var isOutputVerbose: Bool = false
    @Published var isCompressing: Bool = false

    // Template support
    @Published var activeTemplate: PromptTemplate?
    @Published var templatePlaceholderValues: [String: String] = [:]
    @Published var showTemplatePicker: Bool = false

    // Compare mode
    @Published var isCompareMode: Bool = false
    @Published var compareProviders: [LLMProvider] = []
    @Published var compareResults: [CompareResult] = []
    @Published var isComparing: Bool = false

    // Export
    @Published var showExportMenu: Bool = false

    // Command palette
    @Published var showCommandPalette: Bool = false
    @Published var commandPaletteQuery: String = ""

    // Keyboard shortcuts overlay
    @Published var showShortcutsOverlay: Bool = false

    // Explain mode
    @Published var showExplanation: Bool = false
    @Published var currentExplanation: PromptExplanation?

    /// The last optimized output stored independently from the clipboard.
    private(set) var lastOptimizedOutput: String = ""

    private let styleService: StyleService
    private let configurationService: ConfigurationService
    private let historyService: HistoryService
    private let providerManager: LLMProviderManager
    private let promptAssembler: PromptAssembler
    private let clipboardService: ClipboardService
    private let networkMonitor: NetworkMonitor
    private let licensingService: LicensingService
    private let contextEngine: ContextEngineService
    private let complexityClassifier: ComplexityClassifier
    private let postProcessor: PostProcessor
    private let templateService: TemplateService
    private let exportService: ExportService
    private var cancellables = Set<AnyCancellable>()
    private var currentTask: Task<Void, Never>?
    private var clipboardCheckTimer: Timer?

    /// Character count threshold for long input warning.
    private let longInputThreshold = 50_000

    var characterCount: Int {
        inputText.count
    }

    var isOptimizeEnabled: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isProcessing
            && licensingService.canOptimize
    }

    /// Whether the user is on the Pro tier.
    var isProUser: Bool { licensingService.isProUser }

    init(
        styleService: StyleService = .shared,
        configurationService: ConfigurationService = .shared,
        historyService: HistoryService = .shared,
        providerManager: LLMProviderManager = .shared,
        promptAssembler: PromptAssembler = .shared,
        clipboardService: ClipboardService = .shared,
        networkMonitor: NetworkMonitor = .shared,
        licensingService: LicensingService = .shared,
        contextEngine: ContextEngineService = .shared,
        complexityClassifier: ComplexityClassifier = .shared,
        postProcessor: PostProcessor = .shared,
        templateService: TemplateService = .shared,
        exportService: ExportService = .shared
    ) {
        self.styleService = styleService
        self.configurationService = configurationService
        self.historyService = historyService
        self.providerManager = providerManager
        self.promptAssembler = promptAssembler
        self.clipboardService = clipboardService
        self.networkMonitor = networkMonitor
        self.licensingService = licensingService
        self.contextEngine = contextEngine
        self.complexityClassifier = complexityClassifier
        self.postProcessor = postProcessor
        self.templateService = templateService
        self.exportService = exportService

        // Load initial styles
        refreshStyles()

        // Observe style changes
        styleService.$styles
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStyles()
            }
            .store(in: &cancellables)

        // Update description when selection changes
        $selectedStyle
            .map { $0?.shortDescription ?? "" }
            .assign(to: &$selectedStyleDescription)

        // Update complexity preview when input changes (debounced)
        $inputText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.updateComplexityPreview(text)
            }
            .store(in: &cancellables)

        // Listen for reset-all-settings to clear state
        NotificationCenter.default.publisher(for: AppConstants.Notifications.resetAllSettings)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.clearAll() }
            .store(in: &cancellables)

        // Periodically check if output is still on clipboard.
        startClipboardMonitoring()
    }

    deinit {
        clipboardCheckTimer?.invalidate()
    }

    // MARK: - Clipboard Capture

    /// Populate the input area from clipboard text (called by AppDelegate on shortcut activation).
    func populateFromClipboard(_ text: String) {
        inputTruncationWarning = nil
        let maxChars = AppConstants.Clipboard.maxInputCharacters

        if text.count > maxChars {
            inputText = String(text.prefix(maxChars))
            inputTruncationWarning = "Input truncated to \(maxChars.formatted()) characters."
        } else {
            inputText = text
        }
    }

    // MARK: - Optimize

    func optimizePrompt() {
        // Check license/trial gating
        guard licensingService.canOptimize else {
            NotificationCenter.default.post(name: AppConstants.Notifications.navigateToUpgrade, object: nil)
            return
        }

        // Check for long input first — show confirmation if over threshold
        if inputText.count > longInputThreshold && !showLongInputWarning {
            longInputCharCount = inputText.count
            showLongInputWarning = true
            return
        }

        guard isOptimizeEnabled, let style = selectedStyle else { return }

        let config = configurationService.configuration
        let selectedVerbosity = config.outputVerbosity
        let provider = providerManager.activeProvider

        // Check for API key (Ollama and Cloud don't need one via Keychain)
        if config.selectedProvider != .ollama && config.selectedProvider != .promptCraftCloud {
            guard KeychainService.shared.hasAPIKey(for: config.selectedProvider) else {
                errorMessage = LLMError.noAPIKey.errorDescription
                errorSuggestsSettings = true
                outputText = ""
                return
            }
        }

        isProcessing = true
        errorMessage = nil
        errorSuggestsSettings = false
        wasCancelled = false
        isPartialResponse = false
        contextUsed = false
        contextEntryCount = 0
        outputText = ""
        clipboardCopiedNotification = false
        isOutputOnClipboard = false
        showLongInputWarning = false
        isOutputVerbose = false
        isCompressing = false
        detectedMaxOutputWords = 0
        outputVerbosityUsed = nil
        currentExplanation = nil
        showExplanation = false

        let startTime = Date()

        Logger.shared.info("Starting optimization: provider=\(config.selectedProvider.rawValue), model=\(config.selectedModelName)")

        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let assembled = await promptAssembler.assemble(
                    rawInput: inputText,
                    style: style,
                    providerType: config.selectedProvider,
                    verbosity: selectedVerbosity
                )

                let complexity = assembled.complexity
                self.contextUsed = assembled.contextBlock != nil
                self.contextEntryCount = assembled.contextEntryCount
                self.detectedComplexityTier = complexity.tier
                self.complexityContextBoosted = complexity.contextBoosted
                self.detectedMaxOutputWords = complexity.maxOutputWords

                Logger.shared.info("Complexity: tier=\(complexity.tier.rawValue), boosted=\(complexity.contextBoosted), words=\(complexity.wordCount), intents=\(complexity.actionCount), maxOutput=\(complexity.maxOutputWords)")

                // Build the full message array with system message
                var messages: [LLMMessage] = [
                    LLMMessage(role: .system, content: assembled.systemMessage)
                ]
                messages.append(contentsOf: assembled.messages)

                let parameters = LLMRequestParameters(
                    model: config.selectedModelName,
                    temperature: config.temperature,
                    maxTokens: config.maxOutputTokens
                )

                outputText = try await streamCompletion(
                    provider: provider,
                    messages: messages,
                    parameters: parameters
                )

                if Task.isCancelled {
                    wasCancelled = true
                } else {
                    var post = postProcessor.process(
                        outputText: outputText,
                        tier: complexity.tier,
                        maxOutputWords: complexity.maxOutputWords
                    )

                    // Meta leakage fallback: one retry with explicit hard line.
                    if post.shouldRetryForMetaLeak {
                        var retryMessages = messages
                        if let first = retryMessages.first, first.role == .system {
                            retryMessages[0] = LLMMessage(
                                role: .system,
                                content: first.content + "\n\nOutput ONLY the prompt. Zero meta-commentary."
                            )
                        }
                        let retryOutput = try await streamCompletion(
                            provider: provider,
                            messages: retryMessages,
                            parameters: parameters
                        )
                        post = postProcessor.process(
                            outputText: retryOutput,
                            tier: complexity.tier,
                            maxOutputWords: complexity.maxOutputWords
                        )
                    }

                    outputText = post.cleanedOutput
                    self.isOutputVerbose = post.isVerbose

                    // Save history entry
                    let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                    let entry = PromptHistoryEntry(
                        inputText: inputText,
                        outputText: outputText,
                        styleID: style.id,
                        providerName: config.selectedProvider.displayName,
                        modelName: config.selectedModelName,
                        durationMilliseconds: duration
                    )
                    historyService.save(entry)

                    // Index for context engine
                    contextEngine.indexOptimization(
                        inputText: inputText,
                        outputText: outputText,
                        promptID: entry.id,
                        entityAnalysis: assembled.entityAnalysis
                    )

                    // Record calibration analytics
                    let finalOutputWordCount = outputText.split(separator: " ", omittingEmptySubsequences: true).count
                    contextEngine.recordCalibrationAnalytics(
                        promptID: entry.id,
                        detectedTier: complexity.tier,
                        maxOutputWords: complexity.maxOutputWords,
                        actualOutputWords: finalOutputWordCount,
                        compressionTriggered: false,
                        formattingStripped: post.formattingStripped,
                        verbositySetting: selectedVerbosity
                    )

                    // Track optimization count for onboarding guidance
                    OnboardingManager.shared.incrementOptimizationCount()

                    // Store the output independently.
                    lastOptimizedOutput = outputText
                    outputVerbosityUsed = selectedVerbosity

                    // Build explanation from pipeline data (no extra LLM calls).
                    self.currentExplanation = self.buildExplanation(
                        assembled: assembled,
                        post: post,
                        verbosity: selectedVerbosity,
                        config: config
                    )
                    if config.explainModeEnabled {
                        self.showExplanation = true
                    }

                    Logger.shared.info("Optimization complete: \(duration)ms, \(outputText.count) chars")

                    // Auto-copy if enabled
                    if config.autoCopyToClipboard && !outputText.isEmpty {
                        copyOutputToClipboard()
                        showCopiedNotification()
                    }

                    // Quick Optimize auto-close
                    if config.quickOptimizeEnabled && config.quickOptimizeAutoClose {
                        let delay = config.quickOptimizeAutoCloseDelay
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            NotificationCenter.default.post(
                                name: AppConstants.Notifications.closePopover,
                                object: nil
                            )
                        }
                    }
                }
            } catch let error as LLMError {
                handleLLMError(error, config: config)
            } catch {
                if !Task.isCancelled {
                    Logger.shared.error("Optimization failed with unexpected error", error: error)
                    errorMessage = "An unexpected error occurred. Please try again."
                } else {
                    wasCancelled = true
                }
            }

            isProcessing = false
            currentTask = nil
        }
    }

    /// Called when the user confirms a long-input warning.
    func confirmLongInputAndOptimize() {
        showLongInputWarning = false
        optimizePrompt()
    }

    /// Called when the user dismisses a long-input warning.
    func cancelLongInputWarning() {
        showLongInputWarning = false
    }

    // MARK: - Cancel

    func cancelOptimization() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        wasCancelled = true
    }

    // MARK: - Copy

    func copyOutputToClipboard() {
        guard !outputText.isEmpty else { return }
        clipboardService.writeText(outputText)
        isOutputOnClipboard = true
    }

    func selectStyle(_ style: PromptStyle) {
        selectedStyle = style
    }

    // MARK: - Re-optimize

    /// Pre-populate the input field and select the style for re-optimization from history.
    func prepopulateForReoptimize(input: String, styleID: UUID) {
        outputText = ""
        errorMessage = nil
        errorSuggestsSettings = false
        wasCancelled = false
        isPartialResponse = false
        inputTruncationWarning = nil

        populateFromClipboard(input) // handles truncation

        // Select the matching style if available
        if let style = availableStyles.first(where: { $0.id == styleID }) {
            selectedStyle = style
        }
    }

    /// Pre-populate only the input field (user will pick a different style).
    func prepopulateForReoptimize(input: String) {
        outputText = ""
        errorMessage = nil
        errorSuggestsSettings = false
        wasCancelled = false
        isPartialResponse = false
        inputTruncationWarning = nil

        populateFromClipboard(input)
    }

    /// The most recent history entries for the quick-access cards on the main view.
    var recentHistoryEntries: [PromptHistoryEntry] {
        historyService.getRecent(3)
    }

    /// Look up a style display name by ID.
    func styleDisplayName(for styleID: UUID) -> String {
        styleService.getById(styleID)?.displayName ?? "Unknown"
    }

    /// Look up a style icon by ID.
    func styleIconName(for styleID: UUID) -> String {
        styleService.getById(styleID)?.iconName ?? "questionmark"
    }

    /// User-triggered compression. Sends compressed version request to LLM.
    func compressOutput() {
        guard !outputText.isEmpty, !isCompressing else { return }
        let maxWords = detectedMaxOutputWords > 0 ? detectedMaxOutputWords : 50

        isCompressing = true

        let textToCompress = outputText
        let config = configurationService.configuration
        let provider = providerManager.activeProvider

        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let systemMsg = "The previous output was too verbose. Compress to under \(maxWords) words while preserving all meaning."
                let userMsg = "The previous output was too verbose. Compress to under \(maxWords) words while preserving all meaning: \(textToCompress)"

                let messages: [LLMMessage] = [
                    LLMMessage(role: .system, content: systemMsg),
                    LLMMessage(role: .user, content: userMsg)
                ]

                let parameters = LLMRequestParameters(
                    model: config.selectedModelName,
                    temperature: 0.1,
                    maxTokens: config.maxOutputTokens
                )

                var compressed = ""
                let stream = provider.streamCompletion(messages: messages, parameters: parameters)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    compressed += chunk
                }

                if !Task.isCancelled && !compressed.isEmpty {
                    self.outputText = compressed
                    self.isOutputVerbose = false

                    // Record compression analytics
                    let compressedWordCount = compressed.split(separator: " ", omittingEmptySubsequences: true).count
                    self.contextEngine.recordCalibrationAnalytics(
                        promptID: UUID(), // No specific prompt ID for compression
                        detectedTier: self.detectedComplexityTier,
                        maxOutputWords: maxWords,
                        actualOutputWords: compressedWordCount,
                        compressionTriggered: true,
                        formattingStripped: false,
                        verbositySetting: config.outputVerbosity
                    )

                    Logger.shared.info("Compression complete: \(compressedWordCount) words (target: \(maxWords))")
                }
            } catch {
                Logger.shared.error("Compression failed", error: error)
            }

            self.isCompressing = false
            self.currentTask = nil
        }
    }

    private func streamCompletion(
        provider: LLMProviderProtocol,
        messages: [LLMMessage],
        parameters: LLMRequestParameters
    ) async throws -> String {
        var output = ""
        let stream = provider.streamCompletion(messages: messages, parameters: parameters)
        for try await chunk in stream {
            if Task.isCancelled { break }
            output += chunk
        }
        return output
    }

    // MARK: - Private — Error Handling

    private func handleLLMError(_ error: LLMError, config: AppConfiguration) {
        switch error {
        case .cancelled:
            wasCancelled = true
            return

        case .partialResponse(let partial):
            // Show the partial output with a note
            if !partial.isEmpty {
                outputText = partial
            }
            isPartialResponse = true
            errorMessage = error.errorDescription

        case .responseTooLong(let truncated):
            if !truncated.isEmpty {
                outputText = truncated
            }
            errorMessage = error.errorDescription

        case .invalidAPIKey, .noAPIKey:
            errorMessage = error.errorDescription
            errorSuggestsSettings = true

        case .noNetwork:
            errorMessage = error.errorDescription

        case .serviceUnavailable, .timeout:
            var msg = error.errorDescription ?? ""
            msg += fallbackSuggestion(for: config.selectedProvider)
            errorMessage = msg

        default:
            errorMessage = error.errorDescription
        }

        Logger.shared.error("Optimization error: \(error.errorDescription ?? "unknown")")
    }

    /// Suggest an alternative provider when the current one fails.
    private func fallbackSuggestion(for provider: LLMProvider) -> String {
        switch provider {
        case .anthropicClaude:
            return " You can try switching to OpenAI or Ollama in Settings."
        case .openAI:
            return " You can try switching to Claude or Ollama in Settings."
        case .ollama:
            return " Make sure Ollama is running (`ollama serve`)."
        case .custom:
            return " You can try switching to another provider in Settings."
        case .promptCraftCloud:
            return " You can try switching to a different provider in Settings."
        }
    }

    // MARK: - Private — UI Helpers

    private func showCopiedNotification() {
        clipboardCopiedNotification = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.clipboardCopiedNotification = false
        }
    }

    private func updateComplexityPreview(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 10 {
            detectedComplexityTier = complexityClassifier.classifyForPreview(input: trimmed)
        } else {
            detectedComplexityTier = .trivial
        }
    }

    private func startClipboardMonitoring() {
        // Check clipboard every second to see if our output is still there.
        clipboardCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, !self.outputText.isEmpty else { return }
            let current = self.clipboardService.readText()
            DispatchQueue.main.async {
                self.isOutputOnClipboard = (current == self.outputText)
            }
        }
    }

    private func refreshStyles() {
        availableStyles = styleService.getEnabled()
        // Ensure selected style is still valid
        if let current = selectedStyle, !availableStyles.contains(where: { $0.id == current.id }) {
            selectedStyle = availableStyles.first
        }
        if selectedStyle == nil {
            selectedStyle = availableStyles.first
        }
    }

    // MARK: - Template Support

    /// Apply a template: set it as active and populate placeholder values.
    func applyTemplate(_ template: PromptTemplate) {
        activeTemplate = template
        templatePlaceholderValues = [:]
        for placeholder in template.placeholders {
            templatePlaceholderValues[placeholder] = ""
        }
        inputText = template.templateText
        showTemplatePicker = false
    }

    /// Clear the active template.
    func clearTemplate() {
        activeTemplate = nil
        templatePlaceholderValues = [:]
    }

    /// Assemble the template with filled-in values and set as input.
    func assembleTemplate() {
        guard let template = activeTemplate else { return }
        inputText = template.assemble(values: templatePlaceholderValues)
        activeTemplate = nil
    }

    /// Whether all placeholders for the active template have been filled.
    var areAllPlaceholdersFilled: Bool {
        guard let template = activeTemplate else { return false }
        return template.placeholders.allSatisfy { placeholder in
            let value = templatePlaceholderValues[placeholder] ?? ""
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: - Compare Mode

    /// Start a comparison across selected providers.
    func startComparison() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !compareProviders.isEmpty, let style = selectedStyle else { return }
        guard licensingService.canOptimize else {
            NotificationCenter.default.post(name: AppConstants.Notifications.navigateToUpgrade, object: nil)
            return
        }

        isComparing = true
        compareResults = compareProviders.map { provider in
            CompareResult(provider: provider, providerName: provider.displayName)
        }

        let config = configurationService.configuration
        let inputSnapshot = inputText

        for (index, providerType) in compareProviders.enumerated() {
            let provider = providerManager.provider(for: providerType)

            Task { @MainActor [weak self] in
                guard let self else { return }
                let startTime = Date()

                do {
                    // Check API key
                    if providerType != .ollama && providerType != .promptCraftCloud {
                        guard KeychainService.shared.hasAPIKey(for: providerType) else {
                            self.compareResults[index].error = "No API key configured"
                            self.compareResults[index].isComplete = true
                            self.checkCompareCompletion()
                            return
                        }
                    }

                    let assembled = await self.promptAssembler.assemble(
                        rawInput: inputSnapshot,
                        style: style,
                        providerType: providerType,
                        verbosity: config.outputVerbosity
                    )

                    var messages: [LLMMessage] = [
                        LLMMessage(role: .system, content: assembled.systemMessage)
                    ]
                    messages.append(contentsOf: assembled.messages)

                    let modelName = providerType == config.selectedProvider
                        ? config.selectedModelName
                        : providerType.defaultModelName

                    let parameters = LLMRequestParameters(
                        model: modelName,
                        temperature: config.temperature,
                        maxTokens: config.maxOutputTokens
                    )

                    let rawOutput = try await self.streamCompletion(
                        provider: provider,
                        messages: messages,
                        parameters: parameters
                    )
                    let post = self.postProcessor.process(
                        outputText: rawOutput,
                        tier: assembled.complexity.tier,
                        maxOutputWords: assembled.complexity.maxOutputWords
                    )
                    self.compareResults[index].outputText = post.cleanedOutput

                    let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                    self.compareResults[index].durationMs = duration
                    self.compareResults[index].tokenCount = self.estimateTokenCount(self.compareResults[index].outputText)
                    self.compareResults[index].isComplete = true

                } catch {
                    self.compareResults[index].error = error.localizedDescription
                    self.compareResults[index].isComplete = true
                }

                self.checkCompareCompletion()
            }
        }
    }

    /// Check if all compare tasks have finished.
    private func checkCompareCompletion() {
        if compareResults.allSatisfy(\.isComplete) {
            isComparing = false
        }
    }

    /// Use a specific compare result as the output.
    func useCompareResult(_ result: CompareResult) {
        outputText = result.outputText
        lastOptimizedOutput = result.outputText
        outputVerbosityUsed = configurationService.configuration.outputVerbosity
        isCompareMode = false
        compareResults = []
    }

    /// Rough token estimate (words * 1.3).
    private func estimateTokenCount(_ text: String) -> Int {
        let words = text.split(separator: " ").count
        return Int(Double(words) * 1.3)
    }

    // MARK: - Export

    func exportOutput(as format: ExportFormat) {
        exportService.copyFormatted(outputText, as: format)
    }

    func saveOutputToFile() {
        exportService.saveToFile(outputText) { locked in
            NotificationCenter.default.post(
                name: AppConstants.Notifications.lockPopover,
                object: nil,
                userInfo: ["locked": locked]
            )
        }
    }

    // MARK: - Command Palette

    struct CommandItem: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let iconName: String
        let action: () -> Void
    }

    /// Filter command palette results based on query.
    func commandPaletteResults() -> [CommandItem] {
        let query = commandPaletteQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        var items: [CommandItem] = []

        // Styles
        for style in availableStyles {
            if query.isEmpty || style.displayName.lowercased().contains(query) || style.shortDescription.lowercased().contains(query) {
                let s = style
                items.append(CommandItem(
                    title: s.displayName,
                    subtitle: "Style",
                    iconName: s.iconName,
                    action: { [weak self] in self?.selectStyle(s) }
                ))
            }
        }

        // Templates
        for template in templateService.getAll() {
            if query.isEmpty || template.name.lowercased().contains(query) || template.description.lowercased().contains(query) {
                let t = template
                items.append(CommandItem(
                    title: t.name,
                    subtitle: "Template",
                    iconName: t.iconName,
                    action: { [weak self] in self?.applyTemplate(t) }
                ))
            }
        }

        // Recent history
        if query.isEmpty || "recent".contains(query) || "history".contains(query) {
            for entry in historyService.getRecent(3) {
                let e = entry
                let preview = String(e.inputText.prefix(40)).replacingOccurrences(of: "\n", with: " ")
                items.append(CommandItem(
                    title: preview,
                    subtitle: "Recent",
                    iconName: "clock",
                    action: { [weak self] in self?.prepopulateForReoptimize(input: e.inputText, styleID: e.styleID) }
                ))
            }
        }

        // Navigation commands
        let navCommands: [(String, String, String, () -> Void)] = [
            ("Settings", "Open Settings", "gearshape", { [weak self] in
                NotificationCenter.default.post(name: AppConstants.Notifications.navigateToSettings, object: nil)
                self?.showCommandPalette = false
            }),
            ("History", "Open History", "clock.arrow.circlepath", { [weak self] in
                self?.showCommandPalette = false
            }),
            ("New Optimization", "Clear input and output", "plus.circle", { [weak self] in
                self?.clearAll()
                self?.showCommandPalette = false
            }),
        ]

        for (title, subtitle, icon, action) in navCommands {
            if query.isEmpty || title.lowercased().contains(query) || subtitle.lowercased().contains(query) {
                items.append(CommandItem(title: title, subtitle: subtitle, iconName: icon, action: action))
            }
        }

        return items
    }

    // MARK: - Explanation Builder

    private func buildExplanation(
        assembled: PromptAssembler.AssembledPrompt,
        post: PostProcessResult,
        verbosity: OutputVerbosity,
        config: AppConfiguration
    ) -> PromptExplanation {
        let complexity = assembled.complexity
        let intentAnalysis = assembled.intentAnalysis
        let entityAnalysis = assembled.entityAnalysis

        // Build tier reason
        let tierReason = "\(intentAnalysis.intentCount) intent\(intentAnalysis.intentCount == 1 ? "" : "s") detected, ambiguity score \(String(format: "%.2f", complexity.ambiguityScore))"

        // Build entity summary
        var entityParts: [String] = []
        if !entityAnalysis.projects.isEmpty {
            entityParts.append("Projects: \(entityAnalysis.projects.joined(separator: ", "))")
        }
        if !entityAnalysis.environments.isEmpty {
            entityParts.append("Environments: \(entityAnalysis.environments.joined(separator: ", "))")
        }
        if !entityAnalysis.persons.isEmpty {
            entityParts.append("Persons: \(entityAnalysis.persons.joined(separator: ", "))")
        }
        if !entityAnalysis.technicalTerms.isEmpty {
            entityParts.append("Technical: \(entityAnalysis.technicalTerms.joined(separator: ", "))")
        }
        let entitySummary = entityParts.isEmpty ? "None detected" : entityParts.joined(separator: ". ")

        // Count few-shot examples (messages minus the final user message, divided by 2 for user/assistant pairs)
        let fewShotCount = max(0, (assembled.messages.count - 1) / 2)

        // Build post-process actions list
        var postActions: [String] = []
        if post.metaLeakDetected {
            postActions.append("Meta-commentary removed")
        }
        if post.formattingStripped {
            postActions.append("Formatting stripped for Tier 1")
        }
        if post.isVerbose {
            postActions.append("Output flagged as verbose")
        }
        if postActions.isEmpty {
            postActions.append("No post-processing actions taken")
        }

        return PromptExplanation(
            detectedTier: complexity.tier,
            tierReason: tierReason,
            intentCount: intentAnalysis.intentCount,
            intents: intentAnalysis.intents,
            entitySummary: entitySummary,
            contextEntriesUsed: assembled.contextEntryCount,
            contextBoosted: complexity.contextBoosted,
            maxOutputWords: complexity.maxOutputWords,
            verbosityMode: verbosity,
            fewShotExamplesIncluded: fewShotCount,
            emotionalMarkersDetected: intentAnalysis.emotionalMarkers,
            urgencyLevel: intentAnalysis.urgencyLevel,
            postProcessActions: postActions,
            estimatedTokenCount: assembled.estimatedTokenCount,
            providerUsed: config.selectedProvider.displayName,
            modelUsed: config.selectedModelName
        )
    }

    // MARK: - Clear Output

    func clearOutput() {
        outputText = ""
        errorMessage = nil
        errorSuggestsSettings = false
        wasCancelled = false
        isPartialResponse = false
        isCompareMode = false
        compareResults = []
        isOutputVerbose = false
        isOutputOnClipboard = false
        clipboardCopiedNotification = false
        contextUsed = false
        contextEntryCount = 0
        outputVerbosityUsed = nil
        currentExplanation = nil
        showExplanation = false
    }

    // MARK: - Clear All

    func clearAll() {
        inputText = ""
        outputText = ""
        errorMessage = nil
        errorSuggestsSettings = false
        wasCancelled = false
        isPartialResponse = false
        inputTruncationWarning = nil
        isCompareMode = false
        compareResults = []
        activeTemplate = nil
        templatePlaceholderValues = [:]
        outputVerbosityUsed = nil
        currentExplanation = nil
        showExplanation = false
    }

    // MARK: - Select Style by Index

    func selectStyleByIndex(_ index: Int) {
        guard index >= 0, index < availableStyles.count else { return }
        selectStyle(availableStyles[index])
    }
}

// MARK: - CompareResult

struct CompareResult: Identifiable {
    let id = UUID()
    let provider: LLMProvider
    let providerName: String
    var outputText: String = ""
    var durationMs: Int = 0
    var tokenCount: Int = 0
    var error: String?
    var isComplete: Bool = false
}
