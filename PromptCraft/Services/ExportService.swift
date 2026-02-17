import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - System Prompt Destination

/// Destinations for exporting optimized output as a reusable system prompt file.
enum SystemPromptDestination: String, CaseIterable {
    case cursorRules
    case claudeProject
    case chatGPTInstructions
    case systemPromptRaw

    var menuLabel: String {
        switch self {
        case .cursorRules: return "Cursor Rules (.cursorrules)"
        case .claudeProject: return "Claude Project Instructions"
        case .chatGPTInstructions: return "ChatGPT Custom Instructions"
        case .systemPromptRaw: return "Raw System Prompt (.txt)"
        }
    }

    var iconName: String {
        switch self {
        case .cursorRules: return "cursorarrow.rays"
        case .claudeProject: return "doc.text.fill"
        case .chatGPTInstructions: return "text.bubble.fill"
        case .systemPromptRaw: return "doc.plaintext"
        }
    }

    var defaultFilename: String {
        switch self {
        case .cursorRules: return ".cursorrules"
        case .claudeProject: return "system-prompt-claude.md"
        case .chatGPTInstructions: return "chatgpt-instructions.txt"
        case .systemPromptRaw: return "system-prompt.txt"
        }
    }

    var fileContentType: UTType {
        switch self {
        case .cursorRules: return .plainText
        case .claudeProject: return .plainText
        case .chatGPTInstructions: return .plainText
        case .systemPromptRaw: return .plainText
        }
    }
}

/// Metadata describing the optimization context for a system prompt export.
struct SystemPromptMetadata {
    let styleName: String
    let verbosity: String
    let tier: String
}

// MARK: - Export Service

/// Formats and exports optimized prompt output in various formats.
final class ExportService {
    static let shared = ExportService()

    private let configurationService: ConfigurationService

    private init(configurationService: ConfigurationService = .shared) {
        self.configurationService = configurationService
    }

    // MARK: - Format Output

    /// Format the output text according to the specified export format.
    func format(_ text: String, as format: ExportFormat) -> String {
        switch format {
        case .plainText:
            return text

        case .markdown:
            return """
            ```prompt
            \(text)
            ```
            """

        case .claude:
            return "<prompt>\(text)</prompt>"

        case .chatGPT:
            return "Instructions:\n\(text)"

        case .githubIssue:
            return """
            <details><summary>Optimized Prompt</summary>

            \(text)

            </details>
            """

        case .cursorRules, .claudeProject, .chatGPTInstructions, .systemPromptRaw:
            return text
        }
    }

    // MARK: - Copy to Clipboard

    /// Format and copy the output to the clipboard.
    func copyFormatted(_ text: String, as format: ExportFormat) {
        let formatted = self.format(text, as: format)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatted, forType: .string)

        // Remember the last used format
        configurationService.update { $0.defaultExportFormat = format }
    }

    // MARK: - Save to File

    /// Save the output text to a file via save dialog.
    func saveToFile(_ text: String, lockPopover: ((Bool) -> Void)? = nil) {
        lockPopover?(true)
        defer { lockPopover?(false) }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "optimized-prompt.txt"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Export as System Prompt

    /// Export the optimized output as a system prompt file for a specific AI tool destination.
    /// Returns `true` if the user completed the save (did not cancel).
    @discardableResult
    func exportAsSystemPrompt(
        _ text: String,
        destination: SystemPromptDestination,
        metadata: SystemPromptMetadata,
        lockPopover: ((Bool) -> Void)? = nil
    ) -> Bool {
        lockPopover?(true)
        defer { lockPopover?(false) }

        let content = formatSystemPrompt(text, destination: destination, metadata: metadata)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [destination.fileContentType]
        panel.nameFieldStringValue = destination.defaultFilename
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            Logger.shared.error("Failed to save system prompt file", error: error)
            return false
        }
    }

    // MARK: - Private Helpers

    private func formatSystemPrompt(
        _ text: String,
        destination: SystemPromptDestination,
        metadata: SystemPromptMetadata
    ) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())

        switch destination {
        case .cursorRules:
            let header = """
            # Generated by: PromptCraft
            # Date: \(timestamp)
            # Style used: \(metadata.styleName)
            # Verbosity: \(metadata.verbosity)
            # Tier: \(metadata.tier)
            """
            return header + "\n\n" + text

        case .claudeProject:
            let header = """
            <!-- Generated by: PromptCraft -->
            <!-- Date: \(timestamp) -->
            <!-- Style used: \(metadata.styleName) -->
            <!-- Verbosity: \(metadata.verbosity) -->
            <!-- Tier: \(metadata.tier) -->
            """
            return header + "\n\n<instructions>\n" + text + "\n</instructions>"

        case .chatGPTInstructions:
            let header = """
            # Generated by: PromptCraft
            # Date: \(timestamp)
            # Style used: \(metadata.styleName)
            # Verbosity: \(metadata.verbosity)
            # Tier: \(metadata.tier)
            """
            return header + "\n\nYou are an AI assistant. Follow these instructions:\n\n" + text

        case .systemPromptRaw:
            let header = """
            # Generated by: PromptCraft
            # Date: \(timestamp)
            # Style used: \(metadata.styleName)
            # Verbosity: \(metadata.verbosity)
            # Tier: \(metadata.tier)
            """
            return header + "\n\n" + text
        }
    }
}
