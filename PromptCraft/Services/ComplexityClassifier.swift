import Foundation
import NaturalLanguage

// MARK: - Complexity Tier

enum ComplexityTier: String, CaseIterable {
    case trivial
    case simple
    case moderate
    case complex

    var displayLabel: String {
        switch self {
        case .trivial, .simple: return "Quick"
        case .moderate, .complex: return "Detailed"
        }
    }

    var isDetailed: Bool {
        self == .moderate || self == .complex
    }
}

// MARK: - Classification Result

struct ComplexityResult {
    let tier: ComplexityTier
    let contextBoosted: Bool
    let maxOutputWords: Int
    let emotionalMarkersStripped: Bool

    // Raw signals (useful for debugging / tuning)
    let wordCount: Int
    let actionCount: Int
    let ambiguityScore: Float
    let technicalDensity: Float
    let conjunctionCount: Int
}

// MARK: - ComplexityClassifier

final class ComplexityClassifier {
    static let shared = ComplexityClassifier()

    private let vagueTerms: Set<String> = [
        "improve", "better", "fix", "update", "change", "clean",
        "optimize", "enhance", "refactor", "adjust", "tweak",
        "modify", "rework", "redo", "revise", "polish"
    ]

    /// Conjunction/additive words that signal multiple sub-tasks.
    private let conjunctions: Set<String> = [
        "and", "also", "plus", "then", "additionally", "moreover",
        "furthermore", "besides", "meanwhile"
    ]

    /// Phrase-level conjunctions detected via substring.
    private let phraseConjunctions = [
        "after that", "as well as", "in addition", "on top of"
    ]

    /// Urgency words to detect emotional markers.
    private let urgencyWords: Set<String> = [
        "asap", "urgent", "immediately", "now", "hurry",
        "emergency", "critical", "deadline", "rush"
    ]

    /// Common profanity terms for emotion detection.
    private let profanityTerms: Set<String> = [
        "fuck", "fucking", "shit", "shitty", "damn", "damned",
        "hell", "crap", "crappy", "ass", "bullshit", "wtf"
    ]

    private init() {}

    // MARK: - Emotion Detection

    /// Strip emotional markers from text, returning sanitized text and whether emotion was detected.
    func stripEmotionalMarkers(_ text: String) -> (sanitized: String, wasEmotional: Bool) {
        var sanitized = text
        var wasEmotional = false

        // Strip 3+ consecutive ! → single .
        let bangPattern = try! NSRegularExpression(pattern: "!{3,}", options: [])
        let bangRange = NSRange(sanitized.startIndex..., in: sanitized)
        if bangPattern.numberOfMatches(in: sanitized, range: bangRange) > 0 {
            wasEmotional = true
            sanitized = bangPattern.stringByReplacingMatches(in: sanitized, range: bangRange, withTemplate: ".")
        }

        // Lowercase ALL-CAPS words (3+ chars with letters)
        let capsPattern = try! NSRegularExpression(pattern: "\\b([A-Z]{3,})\\b", options: [])
        let capsRange = NSRange(sanitized.startIndex..., in: sanitized)
        let capsMatches = capsPattern.matches(in: sanitized, range: capsRange)
        if !capsMatches.isEmpty {
            var result = sanitized
            for match in capsMatches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let word = String(result[range])
                // Only lowercase if it contains letters (not acronyms like "API")
                if word.rangeOfCharacter(from: .lowercaseLetters) == nil && word.count >= 3 {
                    result.replaceSubrange(range, with: word.lowercased())
                    wasEmotional = true
                }
            }
            sanitized = result
        }

        // Detect urgency words
        let lowerWords = sanitized.lowercased().split(separator: " ").map {
            $0.trimmingCharacters(in: .punctuationCharacters)
        }
        for word in lowerWords {
            if urgencyWords.contains(word) {
                wasEmotional = true
                break
            }
        }

        // Detect profanity
        for word in lowerWords {
            if profanityTerms.contains(word) {
                wasEmotional = true
                break
            }
        }

        return (sanitized, wasEmotional)
    }

    // MARK: - Public API

    /// Classify input text complexity, optionally incorporating context engine signals.
    func classify(
        input: String,
        contextMatches: [ContextSearchResult] = [],
        totalContextEntries: Int = 0,
        verbosity: OutputVerbosity = .concise
    ) -> ComplexityResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ComplexityResult(tier: .trivial, contextBoosted: false,
                                   maxOutputWords: 10, emotionalMarkersStripped: false,
                                   wordCount: 0, actionCount: 0, ambiguityScore: 0,
                                   technicalDensity: 0, conjunctionCount: 0)
        }

        // Apply emotion stripping before all signal computation
        let (sanitized, wasEmotional) = stripEmotionalMarkers(trimmed)

        let words = sanitized.split(separator: " ", omittingEmptySubsequences: true)
        let wordCount = words.count
        let lowercased = sanitized.lowercased()
        let lowercasedWords = words.map { $0.lowercased() }

        // 1. Intent count (verb-based intent clusters)
        let intentCount = countIntents(in: sanitized)

        // 2. Ambiguity score
        let ambiguityScore = computeAmbiguity(words: lowercasedWords, fullText: lowercased)

        // 3. Technical density
        let technicalDensity = computeTechnicalDensity(in: sanitized, wordCount: wordCount)

        // 4. Conjunction count
        let conjunctionCount = countConjunctions(words: lowercasedWords, fullText: lowercased)

        // 5. Context engine boost (capped: trivial→simple only)
        let (contextBoost, contextBoosted) = computeContextBoost(
            matches: contextMatches,
            totalEntries: totalContextEntries
        )

        // 6. Determine base tier from intent-based boundaries
        let baseTier = determineTier(
            wordCount: wordCount,
            intentCount: intentCount,
            ambiguityScore: ambiguityScore,
            technicalDensity: technicalDensity,
            conjunctionCount: conjunctionCount
        )

        // 7. Apply context boost (max +1, trivial→simple only)
        let boostedTier = applyContextBoost(baseTier: baseTier, boost: contextBoost)

        // 8. Apply verbosity adjustment
        let finalTier: ComplexityTier
        switch verbosity {
        case .concise:
            finalTier = boostedTier
        case .balanced:
            let tiers: [ComplexityTier] = [.trivial, .simple, .moderate, .complex]
            if let idx = tiers.firstIndex(of: boostedTier) {
                finalTier = tiers[min(idx + 1, tiers.count - 1)]
            } else {
                finalTier = boostedTier
            }
        case .detailed:
            finalTier = .complex
        }

        // 9. Compute max output words
        let maxOutputWords = computeMaxOutputWords(tier: finalTier, inputWords: wordCount)

        return ComplexityResult(
            tier: finalTier,
            contextBoosted: contextBoosted,
            maxOutputWords: maxOutputWords,
            emotionalMarkersStripped: wasEmotional,
            wordCount: wordCount,
            actionCount: intentCount,
            ambiguityScore: ambiguityScore,
            technicalDensity: technicalDensity,
            conjunctionCount: conjunctionCount
        )
    }

    /// Lightweight classification that skips context signals. Used for the real-time UI chip.
    func classifyForPreview(input: String) -> ComplexityTier {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .trivial }

        let (sanitized, _) = stripEmotionalMarkers(trimmed)

        let words = sanitized.split(separator: " ", omittingEmptySubsequences: true)
        let wordCount = words.count
        let lowercased = sanitized.lowercased()
        let lowercasedWords = words.map { $0.lowercased() }

        let intentCount = countIntents(in: sanitized)
        let ambiguityScore = computeAmbiguity(words: lowercasedWords, fullText: lowercased)
        let technicalDensity = computeTechnicalDensity(in: sanitized, wordCount: wordCount)
        let conjunctionCount = countConjunctions(words: lowercasedWords, fullText: lowercased)

        return determineTier(
            wordCount: wordCount,
            intentCount: intentCount,
            ambiguityScore: ambiguityScore,
            technicalDensity: technicalDensity,
            conjunctionCount: conjunctionCount
        )
    }

    // MARK: - Intent Counting

    /// Count distinct intent clusters — groups of action verbs separated by conjunctions or sentence boundaries.
    private func countIntents(in text: String) -> Int {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let range = text.startIndex..<text.endIndex

        let auxiliaries: Set<String> = [
            "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did",
            "will", "would", "could", "should", "can", "may",
            "might", "shall", "must", "need"
        ]

        // Collect verbs and conjunctions in order
        struct Token {
            let word: String
            let isVerb: Bool
            let isConjunction: Bool
            let isSentenceBoundary: Bool
        }

        var tokens: [Token] = []
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass) { tag, tokenRange in
            let word = String(text[tokenRange]).lowercased()
            let clean = word.trimmingCharacters(in: .punctuationCharacters)

            let isVerb = tag == .verb && !auxiliaries.contains(clean)
            let isConj = self.conjunctions.contains(clean)

            // Check for sentence boundary (period, question mark, exclamation, semicolon)
            let rawWord = String(text[tokenRange])
            let hasBoundary = rawWord.contains(".") || rawWord.contains("?") ||
                              rawWord.contains(";") || rawWord.contains("!")

            tokens.append(Token(word: clean, isVerb: isVerb, isConjunction: isConj, isSentenceBoundary: hasBoundary))
            return true
        }

        // Count intent clusters: a new intent starts after a conjunction or sentence boundary
        // if followed by a verb
        var intentCount = 0
        var currentSegmentHasVerb = false

        for token in tokens {
            if token.isConjunction || token.isSentenceBoundary {
                if currentSegmentHasVerb {
                    intentCount += 1
                    currentSegmentHasVerb = false
                }
            }
            if token.isVerb {
                currentSegmentHasVerb = true
            }
        }

        // Count the last segment
        if currentSegmentHasVerb {
            intentCount += 1
        }

        return max(1, intentCount) // At least 1 intent implied
    }

    // MARK: - Signal Computation

    private func computeAmbiguity(words: [String], fullText: String) -> Float {
        guard !words.isEmpty else { return 0 }

        var vagueCount: Float = 0
        var hasSpecificTarget = false

        for word in words {
            // Check if word (without trailing punctuation) is vague
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            if vagueTerms.contains(clean) {
                vagueCount += 1
            }
        }

        // Check for specificity indicators: file paths, function names, endpoints, line numbers
        let specificityPatterns = [
            "/", ".", "::", "->", "()", "line ", "endpoint", "function ",
            "class ", "method ", "variable ", "file ", "module ", "component ",
            "table ", "column ", "field ", "parameter ", "argument ",
            "route ", "api ", "url ", "port ", "version "
        ]
        for pattern in specificityPatterns {
            if fullText.contains(pattern) {
                hasSpecificTarget = true
                break
            }
        }

        if vagueCount == 0 { return 0.1 }

        let vagueRatio = vagueCount / Float(words.count)
        var score = min(1.0, vagueRatio * 5.0) // Scale up: 20% vague words = 1.0

        // Reduce ambiguity if specific targets are present alongside vague terms
        if hasSpecificTarget {
            score *= 0.5
        }

        return score
    }

    private func computeTechnicalDensity(in text: String, wordCount: Int) -> Float {
        guard wordCount > 0 else { return 0 }

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = text
        let range = text.startIndex..<text.endIndex

        var technicalCount: Float = 0
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass) { tag, tokenRange in
            if let tag {
                let word = String(text[tokenRange])
                // Technical indicators: nouns with camelCase, contains digits, all-caps abbreviations,
                // or contains special chars like hyphens in compound terms
                if tag == .noun || tag == .otherWord {
                    if containsCamelCase(word) || containsDigits(word) ||
                       (word.count >= 2 && word == word.uppercased() && word.rangeOfCharacter(from: .letters) != nil) ||
                       word.contains("-") || word.contains("_") {
                        technicalCount += 1
                    }
                }
            }
            return true
        }

        return min(1.0, technicalCount / Float(wordCount))
    }

    private func countConjunctions(words: [String], fullText: String) -> Int {
        var count = 0
        for word in words {
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            if conjunctions.contains(clean) {
                count += 1
            }
        }
        // Also check for phrase-level conjunctions
        for phrase in phraseConjunctions {
            if fullText.contains(phrase) {
                count += 1
            }
        }
        return count
    }

    // MARK: - Max Output Words

    private func computeMaxOutputWords(tier: ComplexityTier, inputWords: Int) -> Int {
        let raw: Double
        switch tier {
        case .trivial:
            raw = min(Double(inputWords) * 2.0, 50)
        case .simple:
            raw = min(Double(inputWords) * 2.5, 150)
        case .moderate:
            raw = min(Double(inputWords) * 3.0, 400)
        case .complex:
            raw = min(Double(inputWords) * 4.0, 800)
        }
        return max(10, Int(raw)) // Floor: 10 words minimum
    }

    // MARK: - Context Boost (capped: trivial→simple only)

    private func computeContextBoost(
        matches: [ContextSearchResult],
        totalEntries: Int
    ) -> (boost: Int, boosted: Bool) {
        guard !matches.isEmpty else { return (0, false) }

        let highSimilarityMatches = matches.filter { $0.similarity > 0.75 }

        // Only boost if 3+ high-similarity matches and 50+ total entries
        if highSimilarityMatches.count >= 3 && totalEntries >= 50 {
            return (1, true) // Max +1 boost, trivial→simple only
        }

        return (0, false)
    }

    // MARK: - Tier Determination (intent-based boundaries)

    private func determineTier(
        wordCount: Int,
        intentCount: Int,
        ambiguityScore: Float,
        technicalDensity: Float,
        conjunctionCount: Int
    ) -> ComplexityTier {
        // Tier 4 (complex): 5+ intents OR multi-system indicators
        if intentCount >= 5 {
            return .complex
        }

        // Tier 3 (moderate): 3-4 intents OR significant ambiguity
        if intentCount >= 3 || (ambiguityScore >= 0.6 && wordCount >= 40) {
            return .moderate
        }

        // Tier 2 (simple): 2 intents OR 1 complex/ambiguous intent
        if intentCount >= 2 || ambiguityScore >= 0.4 || (wordCount >= 30 && technicalDensity >= 0.3) {
            return .simple
        }

        // Tier 1 (trivial): 1 intent + <100 words
        if intentCount <= 1 && wordCount < 100 {
            return .trivial
        }

        return .simple
    }

    private func applyContextBoost(baseTier: ComplexityTier, boost: Int) -> ComplexityTier {
        guard boost > 0, baseTier == .trivial else { return baseTier }
        // Only boost trivial→simple (max +1, never higher)
        return .simple
    }

    // MARK: - Helpers

    private func containsCamelCase(_ word: String) -> Bool {
        // Has both lower and uppercase letters with an uppercase not at start
        let hasLower = word.rangeOfCharacter(from: .lowercaseLetters) != nil
        let middleAndEnd = word.dropFirst()
        let hasUpperAfterFirst = middleAndEnd.rangeOfCharacter(from: .uppercaseLetters) != nil
        return hasLower && hasUpperAfterFirst
    }

    private func containsDigits(_ word: String) -> Bool {
        word.rangeOfCharacter(from: .decimalDigits) != nil
    }
}
