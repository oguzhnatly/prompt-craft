import Foundation

struct PostProcessResult {
    let cleanedOutput: String
    let isVerbose: Bool
    let formattingStripped: Bool
    let metaLeakDetected: Bool
    let shouldRetryForMetaLeak: Bool
    let compressDirective: String?
}

final class PostProcessor {
    static let shared = PostProcessor()

    private let metaLeakPhrases: [String] = [
        "here is your optimized prompt",
        "i have rewritten",
        "the following prompt",
        "optimized version",
        "enhanced prompt"
    ]

    private init() {}

    func process(outputText: String, tier: ComplexityTier, maxOutputWords: Int) -> PostProcessResult {
        let originalWordCount = countWords(outputText)

        let formatting = enforceTierFormatting(outputText: outputText, tier: tier)
        let meta = removeMetaCommentary(from: formatting.cleaned)

        let finalWordCount = countWords(meta.cleaned)
        let isVerbose = isVerboseOutput(wordCount: finalWordCount, tier: tier, maxOutputWords: maxOutputWords)

        let compressDirective: String?
        if isVerbose && (tier == .trivial || tier == .simple) {
            compressDirective = "The previous output was too verbose. Compress to under \(maxOutputWords) words while preserving all meaning: \(meta.cleaned)"
        } else {
            compressDirective = nil
        }

        let removedWordCount = max(0, originalWordCount - finalWordCount)
        let removedRatio: Double
        if originalWordCount == 0 {
            removedRatio = 0
        } else {
            removedRatio = Double(removedWordCount) / Double(originalWordCount)
        }

        return PostProcessResult(
            cleanedOutput: meta.cleaned,
            isVerbose: isVerbose,
            formattingStripped: formatting.didStrip,
            metaLeakDetected: meta.detected,
            shouldRetryForMetaLeak: meta.detected && removedRatio > 0.3,
            compressDirective: compressDirective
        )
    }

    private func isVerboseOutput(wordCount: Int, tier: ComplexityTier, maxOutputWords: Int) -> Bool {
        guard tier == .trivial || tier == .simple else { return false }
        guard maxOutputWords > 0 else { return false }
        return Double(wordCount) > Double(maxOutputWords) * 1.3
    }

    private func enforceTierFormatting(outputText: String, tier: ComplexityTier) -> (cleaned: String, didStrip: Bool) {
        guard tier == .trivial else {
            return (outputText.trimmingCharacters(in: .whitespacesAndNewlines), false)
        }

        var text = outputText
        var didStrip = false

        if containsMatch(text, pattern: "(?m)^\\s*##+\\s+") {
            text = replaceRegex(text, pattern: "(?m)^\\s*##+\\s+", template: "")
            didStrip = true
        }

        if containsMatch(text, pattern: "(?m)^\\s*\\d+\\.\\s+") {
            text = replaceRegex(text, pattern: "(?m)^\\s*\\d+\\.\\s+", template: "")
            didStrip = true
        }

        if text.contains("**") {
            text = text.replacingOccurrences(of: "**", with: "")
            didStrip = true
        }

        if containsMatch(text, pattern: "(?m)^\\s*[-*]\\s+") {
            text = replaceRegex(text, pattern: "(?m)^\\s*[-*]\\s+", template: "")
            didStrip = true
        }

        if didStrip {
            text = joinLinesAsProse(text)
        }

        return (text.trimmingCharacters(in: .whitespacesAndNewlines), didStrip)
    }

    private func removeMetaCommentary(from text: String) -> (cleaned: String, detected: Bool) {
        guard !text.isEmpty else { return (text, false) }

        var detected = false
        var cleanedSentences: [String] = []

        let sentences = splitIntoSentences(text)
        for sentence in sentences {
            let lower = sentence.lowercased()
            if metaLeakPhrases.contains(where: { lower.contains($0) }) {
                detected = true
                continue
            }
            cleanedSentences.append(sentence)
        }

        let cleaned = cleanedSentences.joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (cleaned.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned, detected)
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        if let regex = try? NSRegularExpression(pattern: "[^.!?]+[.!?]?", options: []) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            return regex.matches(in: normalized, range: range).compactMap { match in
                guard let r = Range(match.range, in: normalized) else { return nil }
                return String(normalized[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        }

        return [normalized]
    }

    private func joinLinesAsProse(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var prose = ""
        for line in lines {
            if prose.isEmpty {
                prose = line
                continue
            }

            if prose.hasSuffix(".") || prose.hasSuffix("!") || prose.hasSuffix("?") {
                prose += " \(line)"
            } else {
                prose += ". \(line)"
            }
        }

        return prose
    }

    private func countWords(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func replaceRegex(_ text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private func containsMatch(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
