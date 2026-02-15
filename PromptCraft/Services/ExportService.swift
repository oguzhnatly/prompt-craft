import AppKit
import Foundation
import UniformTypeIdentifiers

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
}
