import Foundation

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

    var tierNumber: Int {
        switch self {
        case .trivial: return 1
        case .simple: return 2
        case .moderate: return 3
        case .complex: return 4
        }
    }
}

// MARK: - Classification Result

struct ComplexityResult {
    let tier: ComplexityTier
    let contextBoosted: Bool
    let maxOutputWords: Int
    let emotionalMarkersStripped: Bool

    // Raw signals
    let wordCount: Int
    let actionCount: Int
    let ambiguityScore: Float
    let technicalDensity: Float
    let conjunctionCount: Int
    let multiSystemDetected: Bool
}

// MARK: - ComplexityClassifier

final class ComplexityClassifier {
    static let shared = ComplexityClassifier()

    private let vagueSingleTerms: Set<String> = [
        "improve", "better", "fix", "update", "cleanup", "clean", "optimize"
    ]

    private let vaguePhrases: [String] = [
        "make it better",
        "clean up",
        "make better"
    ]

    private let specificVerbs: Set<String> = [
        "debug", "investigate", "profile", "validate", "implement", "refactor", "triage", "reproduce", "trace", "benchmark", "deploy", "rollback"
    ]

    private let genericObjects: Set<String> = [
        "it", "this", "that", "thing", "stuff", "task", "issue"
    ]

    private let conjunctionWords: Set<String> = [
        "and", "also", "plus", "then", "after", "next"
    ]

    private let intentDecomposer = IntentDecomposer.shared
    private let entityExtractor = EntityExtractor.shared

    private init() {}

    // MARK: - Public API

    func classify(
        intentAnalysis: IntentAnalysis,
        entityAnalysis: EntityAnalysis,
        contextMatches: [ContextSearchResult] = [],
        totalContextEntries: Int = 0,
        verbosity: OutputVerbosity = .concise
    ) -> ComplexityResult {
        let cleaned = intentAnalysis.cleanedInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = cleaned.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let inputWordCount = words.count

        let ambiguityScore = computeAmbiguityScore(intentAnalysis: intentAnalysis)
        let conjunctionCount = words.reduce(0) { partial, word in
            let token = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            return partial + (conjunctionWords.contains(token) ? 1 : 0)
        }

        let technicalSignalCount = entityAnalysis.technicalTerms.count + entityAnalysis.projects.count + entityAnalysis.environments.count
        let technicalDensity: Float
        if inputWordCount == 0 {
            technicalDensity = 0
        } else {
            technicalDensity = min(1.0, Float(technicalSignalCount) / Float(max(1, inputWordCount)))
        }

        let multiSystemDetected = detectMultiSystem(entityAnalysis: entityAnalysis, text: cleaned)

        var baseTier = determineBaseTier(
            intentCount: intentAnalysis.intentCount,
            ambiguityScore: ambiguityScore,
            multiSystemDetected: multiSystemDetected
        )

        let shouldBoost = shouldApplyContextBoost(
            baseTier: baseTier,
            matches: contextMatches,
            totalContextEntries: totalContextEntries
        )

        if shouldBoost && baseTier == .trivial {
            baseTier = .simple
        }

        let adjustedTier = adjustTierForVerbosity(baseTier, verbosity: verbosity)
        let maxOutputWords = computeMaxOutputWords(tier: adjustedTier, inputWords: inputWordCount)

        return ComplexityResult(
            tier: adjustedTier,
            contextBoosted: shouldBoost,
            maxOutputWords: maxOutputWords,
            emotionalMarkersStripped: !intentAnalysis.emotionalMarkers.isEmpty,
            wordCount: inputWordCount,
            actionCount: intentAnalysis.intentCount,
            ambiguityScore: ambiguityScore,
            technicalDensity: technicalDensity,
            conjunctionCount: conjunctionCount,
            multiSystemDetected: multiSystemDetected
        )
    }

    /// Compatibility wrapper for older call sites.
    func classify(
        input: String,
        contextMatches: [ContextSearchResult] = [],
        totalContextEntries: Int = 0,
        verbosity: OutputVerbosity = .concise
    ) -> ComplexityResult {
        let intent = intentDecomposer.analyze(input)
        let entities = entityExtractor.analyze(input)
        return classify(
            intentAnalysis: intent,
            entityAnalysis: entities,
            contextMatches: contextMatches,
            totalContextEntries: totalContextEntries,
            verbosity: verbosity
        )
    }

    /// Lightweight preview classification for the live UI chip.
    func classifyForPreview(input: String) -> ComplexityTier {
        let intent = intentDecomposer.analyze(input)
        let entities = entityExtractor.analyze(input)
        let result = classify(
            intentAnalysis: intent,
            entityAnalysis: entities,
            contextMatches: [],
            totalContextEntries: 0,
            verbosity: .concise
        )
        return result.tier
    }

    // MARK: - Ambiguity

    private func computeAmbiguityScore(intentAnalysis: IntentAnalysis) -> Float {
        let cleaned = intentAnalysis.cleanedInput.lowercased()
        var score: Float = 0

        for phrase in vaguePhrases where cleaned.contains(phrase) {
            score += 0.2
        }

        for intent in intentAnalysis.intents {
            let verb = intent.verb.lowercased()
            let object = intent.object.lowercased()

            if vagueSingleTerms.contains(verb) && (object.isEmpty || genericObjects.contains(object) || object.count <= 2) {
                score += 0.2
            }

            if specificVerbs.contains(verb) && !genericObjects.contains(object) && object.count > 2 {
                score -= 0.1
            }

            if vagueSingleTerms.contains(verb) && !genericObjects.contains(object) && object.count > 2 {
                score -= 0.05
            }
        }

        if intentAnalysis.intents.isEmpty {
            score += 0.2
        }

        return min(1.0, max(0.0, score))
    }

    // MARK: - Tier Decision Tree

    private func determineBaseTier(intentCount: Int, ambiguityScore: Float, multiSystemDetected: Bool) -> ComplexityTier {
        if intentCount >= 5 || ambiguityScore > 0.7 || multiSystemDetected {
            return .complex
        }

        if (3...4).contains(intentCount) || (ambiguityScore >= 0.5 && ambiguityScore <= 0.7) {
            return .moderate
        }

        if intentCount == 2 || (intentCount == 1 && ambiguityScore >= 0.3 && ambiguityScore <= 0.5) {
            return .simple
        }

        if intentCount == 1 && ambiguityScore < 0.3 {
            return .trivial
        }

        return .simple
    }

    private func detectMultiSystem(entityAnalysis: EntityAnalysis, text: String) -> Bool {
        if entityAnalysis.environments.count >= 2 { return true }

        let uniqueProjects = Set(entityAnalysis.projects.map { $0.lowercased() })
        if uniqueProjects.count >= 3 { return true }
        if uniqueProjects.count >= 2 && entityAnalysis.environments.count >= 2 { return true }

        let lowered = text.lowercased()
        let multiSystemPhrases = [
            "frontend and backend",
            "api and database",
            "client and server",
            "mobile and web",
            "service and worker"
        ]

        return multiSystemPhrases.contains(where: lowered.contains)
    }

    // MARK: - Context Boost

    private func shouldApplyContextBoost(
        baseTier: ComplexityTier,
        matches: [ContextSearchResult],
        totalContextEntries: Int
    ) -> Bool {
        guard baseTier == .trivial else { return false }
        guard totalContextEntries >= 50 else { return false }

        let strongMatches = matches.filter { $0.similarity > 0.75 }
        guard strongMatches.count >= 3 else { return false }

        let groupedByCluster = Dictionary(grouping: strongMatches) { $0.entry.clusterID }
        for (clusterID, grouped) in groupedByCluster {
            guard clusterID != nil else { continue }
            if grouped.count >= 3 {
                return true
            }
        }

        // Fallback when cluster assignments are not present yet.
        return strongMatches.count >= 3
    }

    // MARK: - Verbosity

    private func adjustTierForVerbosity(_ tier: ComplexityTier, verbosity: OutputVerbosity) -> ComplexityTier {
        switch verbosity {
        case .concise:
            return tier

        case .balanced:
            switch tier {
            case .trivial: return .simple
            case .simple: return .moderate
            case .moderate, .complex: return .complex
            }

        case .detailed:
            return .complex
        }
    }

    // MARK: - 2x Rule Output Budget

    private func computeMaxOutputWords(tier: ComplexityTier, inputWords: Int) -> Int {
        guard inputWords > 0 else {
            switch tier {
            case .trivial: return 20
            case .simple: return 40
            case .moderate: return 120
            case .complex: return 250
            }
        }

        let maxWords: Double
        switch tier {
        case .trivial:
            maxWords = min(Double(inputWords) * 2.0, 50)
        case .simple:
            maxWords = min(Double(inputWords) * 2.5, 150)
        case .moderate:
            maxWords = min(Double(inputWords) * 3.0, 400)
        case .complex:
            maxWords = min(Double(inputWords) * 4.0, 800)
        }

        return max(8, Int(ceil(maxWords)))
    }
}
