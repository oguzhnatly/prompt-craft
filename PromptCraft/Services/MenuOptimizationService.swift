import Foundation

final class MenuOptimizationService {
    static let shared = MenuOptimizationService()

    private let clipboardService = ClipboardService.shared
    private let styleService = StyleService.shared
    private let configService = ConfigurationService.shared
    private let providerManager = LLMProviderManager.shared
    private let promptAssembler = PromptAssembler.shared
    private let historyService = HistoryService.shared
    private let contextEngine = ContextEngineService.shared
    private let notificationService = NotificationService.shared
    private let postProcessor = PostProcessor.shared

    private init() {}

    // MARK: - Quick Optimize

    /// Optimize clipboard contents using the last-used style (or General as default).
    func quickOptimizeClipboard() {
        let config = configService.configuration
        let styleID = config.lastUsedStyleID ?? DefaultStyles.defaultStyleID
        optimizeClipboard(with: styleID)
    }

    /// Optimize clipboard contents with a specific style.
    func optimizeClipboard(with styleID: UUID) {
        guard let text = clipboardService.readText(), !text.isEmpty else {
            notificationService.notifyOptimizationFailed(error: "Clipboard is empty or contains non-text data.")
            return
        }

        guard let style = styleService.getByIdIncludingInternal(styleID) else {
            notificationService.notifyOptimizationFailed(error: "Style not found.")
            return
        }

        let config = configService.configuration

        // Check for API key (Ollama doesn't need one)
        if config.selectedProvider != .ollama {
            guard KeychainService.shared.hasAPIKey(for: config.selectedProvider) else {
                notificationService.notifyOptimizationFailed(error: "No API key configured. Open Settings to add one.")
                return
            }
        }

        // Update last used style
        configService.update { $0.lastUsedStyleID = styleID }

        let provider = providerManager.activeProvider
        let startTime = Date()

        Logger.shared.info("Menu optimization: style=\(style.displayName), provider=\(config.selectedProvider.rawValue)")

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let assembled = await self.promptAssembler.assemble(
                    rawInput: text,
                    style: style,
                    providerType: config.selectedProvider,
                    verbosity: config.outputVerbosity
                )

                var messages: [LLMMessage] = [
                    LLMMessage(role: .system, content: assembled.systemMessage)
                ]
                messages.append(contentsOf: assembled.messages)

                let parameters = LLMRequestParameters(
                    model: config.selectedModelName,
                    temperature: config.temperature,
                    maxTokens: config.maxOutputTokens
                )

                var output = ""
                let stream = provider.streamCompletion(messages: messages, parameters: parameters)
                for try await chunk in stream {
                    output += chunk
                }

                var post = self.postProcessor.process(
                    outputText: output,
                    tier: assembled.complexity.tier,
                    maxOutputWords: assembled.complexity.maxOutputWords
                )

                if post.shouldRetryForMetaLeak {
                    var retryMessages = messages
                    if let first = retryMessages.first, first.role == .system {
                        retryMessages[0] = LLMMessage(
                            role: .system,
                            content: first.content + "\n\nOutput ONLY the prompt. Zero meta-commentary."
                        )
                    }

                    var retriedOutput = ""
                    let retryStream = provider.streamCompletion(messages: retryMessages, parameters: parameters)
                    for try await chunk in retryStream {
                        retriedOutput += chunk
                    }
                    post = self.postProcessor.process(
                        outputText: retriedOutput,
                        tier: assembled.complexity.tier,
                        maxOutputWords: assembled.complexity.maxOutputWords
                    )
                }

                output = post.cleanedOutput

                guard !output.isEmpty else {
                    await MainActor.run {
                        self.notificationService.notifyOptimizationFailed(error: "Empty response from provider.")
                    }
                    return
                }

                // Write result to clipboard
                await MainActor.run {
                    self.clipboardService.writeText(output)
                }

                // Save history
                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                let entry = PromptHistoryEntry(
                    inputText: text,
                    outputText: output,
                    styleID: style.id,
                    providerName: config.selectedProvider.displayName,
                    modelName: config.selectedModelName,
                    durationMilliseconds: duration
                )

                await MainActor.run {
                    self.historyService.save(entry)
                    self.contextEngine.indexOptimization(
                        inputText: text,
                        outputText: output,
                        promptID: entry.id,
                        entityAnalysis: assembled.entityAnalysis
                    )
                    self.notificationService.notifyOptimizationComplete(
                        style: style.displayName,
                        characterCount: output.count
                    )
                }

                Logger.shared.info("Menu optimization complete: \(duration)ms, \(output.count) chars")

            } catch {
                Logger.shared.error("Menu optimization failed", error: error)
                await MainActor.run {
                    self.notificationService.notifyOptimizationFailed(
                        error: "Optimization failed: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
}
