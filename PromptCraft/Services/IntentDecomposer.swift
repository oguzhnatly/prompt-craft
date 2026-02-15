import Foundation
import NaturalLanguage

struct Intent: Codable, Equatable {
    let verb: String
    let object: String
}

struct IntentAnalysis: Codable, Equatable {
    let intents: [Intent]
    let intentCount: Int
    let urgencyLevel: Int
    let emotionalMarkers: [String]
    let cleanedInput: String
    let rawInput: String
}

final class IntentDecomposer {
    static let shared = IntentDecomposer()

    private let profanityTerms: Set<String> = [
        "fuck", "fucking", "shit", "shitty", "damn", "hell", "wtf", "crap", "bullshit"
    ]

    private let urgencyTerms: Set<String> = [
        "immediately", "right now", "asap", "urgent", "fix now", "please fix", "now"
    ]

    private let conjunctionPatterns: [String] = [
        "\\band\\b",
        "\\balso\\b",
        "\\bplus\\b",
        "\\bthen\\b",
        "\\bafter that\\b"
    ]

    private let fillerPatterns: [String] = [
        "\\bwhy\\b",
        "\\bplease\\b",
        "\\bcan you\\b",
        "\\bcould you\\b",
        "\\bjust\\b",
        "\\breally\\b",
        "\\bthe\\b",
        "\\bmy\\b"
    ]

    private let auxiliaryVerbs: Set<String> = [
        "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did",
        "can", "could", "would", "should", "will", "may", "might", "must"
    ]

    private let technicalAcronyms: Set<String> = [
        "API", "SQL", "HTTP", "HTTPS", "TCP", "UDP", "AWS", "GCP", "VPS", "CPU", "GPU", "RAM", "DNS"
    ]

    private init() {}

    func analyze(_ rawInput: String) -> IntentAnalysis {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return IntentAnalysis(
                intents: [],
                intentCount: 0,
                urgencyLevel: 0,
                emotionalMarkers: [],
                cleanedInput: "",
                rawInput: rawInput
            )
        }

        let emotionalMarkers = detectEmotionalMarkers(in: trimmed)
        let urgencyLevel = mapUrgencyLevel(markerCount: emotionalMarkers.count)
        let cleanedInput = cleanInput(trimmed, emotionalMarkers: emotionalMarkers)

        let extractedIntents = extractIntents(from: cleanedInput)
        let intents: [Intent]
        if extractedIntents.isEmpty {
            intents = [inferImplicitIntent(from: cleanedInput, fallbackRaw: trimmed)]
        } else {
            intents = dedupeIntents(extractedIntents)
        }

        return IntentAnalysis(
            intents: intents,
            intentCount: max(1, intents.count),
            urgencyLevel: urgencyLevel,
            emotionalMarkers: emotionalMarkers,
            cleanedInput: cleanedInput,
            rawInput: rawInput
        )
    }

    private func detectEmotionalMarkers(in text: String) -> [String] {
        var markers: [String] = []

        let lowered = text.lowercased()
        let tokens = lowered
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }

        for token in tokens where profanityTerms.contains(token) {
            markers.append(token)
        }

        if let regex = try? NSRegularExpression(pattern: "[!?]{3,}") {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let r = Range(match.range, in: text) {
                    let cluster = String(text[r])
                    markers.append(cluster)
                    // Density sensitive weighting for very emotional punctuation bursts.
                    if cluster.count > 1 {
                        for _ in 0..<(cluster.count - 1) {
                            markers.append(cluster)
                        }
                    }
                }
            }
        }

        for urgency in urgencyTerms {
            if lowered.range(of: urgency, options: .caseInsensitive) != nil {
                markers.append(urgency)
            }
        }

        if let regex = try? NSRegularExpression(pattern: "\\b[A-Z]{3,}\\b") {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let r = Range(match.range, in: text) {
                    let token = String(text[r])
                    if !technicalAcronyms.contains(token) {
                        markers.append(token)
                    }
                }
            }
        }

        return markers
    }

    private func mapUrgencyLevel(markerCount: Int) -> Int {
        switch markerCount {
        case 0:
            return 0
        case 1...2:
            return 1
        case 3...5:
            return 2
        default:
            return 3
        }
    }

    private func cleanInput(_ text: String, emotionalMarkers: [String]) -> String {
        var cleaned = text

        for marker in emotionalMarkers.sorted(by: { $0.count > $1.count }) where !marker.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: marker)
            if let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: " ")
            }
        }

        for profanity in profanityTerms {
            if let regex = try? NSRegularExpression(pattern: "\\b\(profanity)\\b", options: [.caseInsensitive]) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: " ")
            }
        }

        for urgency in urgencyTerms.sorted(by: { $0.count > $1.count }) {
            let escaped = NSRegularExpression.escapedPattern(for: urgency)
            if let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: " ")
            }
        }

        for filler in fillerPatterns {
            if let regex = try? NSRegularExpression(pattern: filler, options: [.caseInsensitive]) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: " ")
            }
        }

        if let punctuationRegex = try? NSRegularExpression(pattern: "[!?]{2,}") {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = punctuationRegex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: " ")
        }

        cleaned = cleaned.replacingOccurrences(of: " in my ", with: " in ", options: [.caseInsensitive])
        cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")

        let normalized = cleaned
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        return normalized.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : normalized
    }

    private func extractIntents(from text: String) -> [Intent] {
        let segments = splitCompoundIntents(text)
        guard !segments.isEmpty else { return [] }

        var intents: [Intent] = []
        for segment in segments {
            intents.append(contentsOf: extractVerbObjectPairs(from: segment))
        }
        return intents
    }

    private func splitCompoundIntents(_ text: String) -> [String] {
        var working = text
        for pattern in conjunctionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(working.startIndex..., in: working)
                working = regex.stringByReplacingMatches(in: working, range: range, withTemplate: " ||| ")
            }
        }

        let sentenceSplit = working
            .replacingOccurrences(of: ";", with: " ||| ")
            .replacingOccurrences(of: ".", with: " ||| ")
            .replacingOccurrences(of: "\n", with: " ||| ")

        return sentenceSplit
            .components(separatedBy: "|||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }
    }

    private struct TaggedToken {
        let text: String
        let index: Int
        let tag: NLTag?
    }

    private func extractVerbObjectPairs(from segment: String) -> [Intent] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = segment
        let range = segment.startIndex..<segment.endIndex

        var tokens: [TaggedToken] = []
        var tokenIndex = 0

        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, tokenRange in
            let token = String(segment[tokenRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                tokens.append(TaggedToken(text: token, index: tokenIndex, tag: tag))
                tokenIndex += 1
            }
            return true
        }

        guard !tokens.isEmpty else { return [] }

        var intents: [Intent] = []

        for token in tokens where token.tag == .verb {
            let normalizedVerb = normalizeToken(token.text)
            if normalizedVerb.isEmpty || auxiliaryVerbs.contains(normalizedVerb) {
                continue
            }

            let object = nearestNoun(to: token, in: tokens) ?? inferObjectPhrase(after: token.index, in: tokens)
            intents.append(Intent(verb: normalizedVerb, object: object))
        }

        return intents
    }

    private func nearestNoun(to verbToken: TaggedToken, in tokens: [TaggedToken]) -> String? {
        let nounTags: Set<NLTag> = [.noun, .personalName, .placeName, .organizationName]

        let sorted = tokens
            .filter { token in
                guard let tag = token.tag else { return false }
                return nounTags.contains(tag)
            }
            .sorted { abs($0.index - verbToken.index) < abs($1.index - verbToken.index) }

        guard let candidate = sorted.first else { return nil }
        let normalized = normalizeToken(candidate.text)
        return normalized.isEmpty ? nil : normalized
    }

    private func inferObjectPhrase(after verbIndex: Int, in tokens: [TaggedToken]) -> String {
        let slice = tokens
            .filter { $0.index > verbIndex }
            .prefix(3)
            .map { normalizeToken($0.text) }
            .filter { !$0.isEmpty }

        if !slice.isEmpty {
            return slice.joined(separator: " ")
        }

        return "task"
    }

    private func inferImplicitIntent(from cleanedInput: String, fallbackRaw: String) -> Intent {
        let lowered = cleanedInput.lowercased()

        if lowered.contains("doesn't trigger") || lowered.contains("doesnt trigger") || lowered.contains("not trigger") || lowered.contains("fails") || lowered.contains("broken") {
            let probableObject = firstTechnicalLikeToken(in: cleanedInput) ?? "issue"
            return Intent(verb: "debug", object: probableObject)
        }

        let verbs = ["fix", "add", "update", "refactor", "debug", "write", "build", "check"]
        for verb in verbs where lowered.contains("\(verb)") {
            let object = firstTechnicalLikeToken(in: cleanedInput) ?? "task"
            return Intent(verb: verb, object: object)
        }

        let fallbackObject = firstTechnicalLikeToken(in: cleanedInput) ?? fallbackRaw
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Intent(verb: "analyze", object: fallbackObject)
    }

    private func firstTechnicalLikeToken(in text: String) -> String? {
        let parts = text
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }

        for part in parts {
            if part.count < 3 { continue }
            if part.contains("_") || part.contains("/") || part.contains(".") || part.contains("-") {
                return part.lowercased()
            }
            if part.lowercased() == "local" || part.lowercased() == "staging" || part.lowercased() == "prod" {
                continue
            }
            if part.rangeOfCharacter(from: .decimalDigits) != nil {
                return part.lowercased()
            }
            if part == part.lowercased() {
                return part.lowercased()
            }
        }

        return nil
    }

    private func dedupeIntents(_ intents: [Intent]) -> [Intent] {
        var seen = Set<String>()
        var deduped: [Intent] = []

        for intent in intents {
            let verb = normalizeToken(intent.verb)
            let object = normalizeToken(intent.object)
            guard !verb.isEmpty, !object.isEmpty else { continue }

            let key = "\(verb)::\(object)"
            if seen.insert(key).inserted {
                deduped.append(Intent(verb: verb, object: object))
            }
        }

        return deduped
    }

    private func normalizeToken(_ token: String) -> String {
        token
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
    }
}
