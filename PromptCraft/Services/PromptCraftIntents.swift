import AppIntents
import Foundation

// MARK: - PromptCraft App Intents
// Registers actions that appear in:
// - Shortcuts.app (macOS Shortcuts / Automations)
// - Spotlight (type "PromptCraft" or action names to surface these)
// - Siri on macOS

// MARK: - Optimize Prompt Intent

/// Optimize a prompt through the 7-stage RMPA pipeline and return the result.
struct OptimizePromptIntent: AppIntent {
    static var title: LocalizedStringResource = "Optimize Prompt"
    static var description = IntentDescription(
        "Sends a prompt through PromptCraft's 7-stage optimization pipeline and returns the improved version.",
        categoryName: "Prompt Engineering"
    )

    // Input parameter
    @Parameter(title: "Prompt", description: "The raw prompt text to optimize.")
    var promptText: String

    @Parameter(title: "Style", description: "The optimization style to apply.", default: "General")
    var styleName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Optimize \(\.$promptText) using \(\.$styleName) style")
    }

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            Task {
                do {
                    let optimized = try await PromptCraftIntents.optimizePrompt(
                        text: promptText,
                        styleName: styleName
                    )
                    continuation.resume(returning: optimized)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return .result(value: result)
    }
}

// MARK: - Optimize Clipboard Intent

/// Grab the current clipboard contents, optimize them, and copy the result back.
struct OptimizeClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Optimize Clipboard Prompt"
    static var description = IntentDescription(
        "Reads the current clipboard, optimizes the text through PromptCraft, and copies the result back to the clipboard.",
        categoryName: "Prompt Engineering"
    )

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        guard let clipboardText = NSPasteboard.general.string(forType: .string), !clipboardText.isEmpty else {
            return .result(dialog: "Clipboard is empty. Copy a prompt first.")
        }

        let optimized = try await PromptCraftIntents.optimizePrompt(text: clipboardText, styleName: "General")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(optimized, forType: .string)

        return .result(dialog: "Done! Optimized prompt copied to clipboard.")
    }
}

// MARK: - Open PromptCraft Intent

/// Open the PromptCraft popover / desktop window.
struct OpenPromptCraftIntent: AppIntent {
    static var title: LocalizedStringResource = "Open PromptCraft"
    static var description = IntentDescription(
        "Opens the PromptCraft window or menu bar popover.",
        categoryName: "App Control"
    )

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: AppConstants.Notifications.shortcutActivated, object: nil)
        return .result()
    }
}

// MARK: - Clear History Intent

/// Clear all optimization history.
struct ClearHistoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Clear Optimization History"
    static var description = IntentDescription(
        "Clears all entries from PromptCraft's optimization history.",
        categoryName: "App Control"
    )

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        HistoryService.shared.clearAll()
        return .result(dialog: "History cleared.")
    }
}

// MARK: - Shortcut Provider

/// Registers PromptCraft as a Shortcut-aware app and supplies default shortcut suggestions.
struct PromptCraftShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OptimizeClipboardIntent(),
            phrases: [
                "Optimize clipboard with \(.applicationName)",
                "Improve my prompt with \(.applicationName)",
            ],
            shortTitle: "Optimize Clipboard",
            systemImageName: "wand.and.stars"
        )
        AppShortcut(
            intent: OpenPromptCraftIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show \(.applicationName)",
            ],
            shortTitle: "Open PromptCraft",
            systemImageName: "rectangle.stack.fill"
        )
    }
}

// MARK: - Internal Helper

/// Shared optimization helper used by intents (avoids duplicating provider logic).
private enum PromptCraftIntents {

    @MainActor
    static func optimizePrompt(text: String, styleName: String) async throws -> String {
        let styleService = StyleService.shared
        let styles = styleService.allStyles()
        let style = styles.first { $0.name.lowercased() == styleName.lowercased() }
            ?? styles.first { $0.name == "General" }
            ?? styles.first
            ?? DefaultStyles.general

        let provider = LLMProviderManager.shared
        let config = ConfigurationService.shared.configuration

        let assembled = await PromptAssembler.shared.assemble(
            rawInput: text,
            style: style,
            providerType: config.selectedProvider,
            verbosity: config.outputVerbosity
        )

        var output = ""
        let stream = provider.activeProvider.streamCompletion(
            messages: assembled.messages.map { LLMMessage(role: $0.role, content: $0.content) },
            parameters: LLMRequestParameters(
                model: config.selectedModelName,
                temperature: config.temperature,
                maxTokens: config.maxOutputTokens
            )
        )

        for try await chunk in stream {
            output += chunk
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
