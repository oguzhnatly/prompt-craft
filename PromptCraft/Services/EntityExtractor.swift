import Foundation
import NaturalLanguage

struct EntityAnalysis: Codable, Equatable {
    let persons: [String]
    let projects: [String]
    let environments: [String]
    let technicalTerms: [String]
    let temporalMarkers: [String]
    let organizations: [String]

    static let empty = EntityAnalysis(
        persons: [],
        projects: [],
        environments: [],
        technicalTerms: [],
        temporalMarkers: [],
        organizations: []
    )
}

final class EntityExtractor {
    static let shared = EntityExtractor()

    private let environmentTerms: Set<String> = [
        "local", "staging", "prod", "production", "vps", "server", "cloud", "docker", "k8s", "kubernetes", "aws", "gcp", "azure"
    ]

    private let personStopwords: Set<String> = [
        "the", "and", "or", "if", "else", "you", "your", "my", "our", "team", "project", "issue", "bug", "task", "please", "now"
    ]

    private let commonWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "into", "within", "working", "update", "fix", "bug", "issue", "local", "staging",
        "production", "user", "users", "system", "service", "module", "component", "feature", "new", "old", "check", "make", "add", "remove", "change"
    ]

    private init() {}

    func analyze(_ rawInput: String) -> EntityAnalysis {
        let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }

        var persons: [String] = []
        var projects: [String] = []
        var environments: [String] = []
        var technicalTerms: [String] = []
        var temporalMarkers: [String] = []
        var organizations: [String] = []

        persons.append(contentsOf: detectPersons(in: text))

        let projectDetection = detectProjectsAndEnvironments(in: text)
        projects.append(contentsOf: projectDetection.projects)
        environments.append(contentsOf: projectDetection.environments)

        technicalTerms.append(contentsOf: detectTechnicalTerms(in: text, knownProjects: projects, knownEnvironments: environments))
        temporalMarkers.append(contentsOf: detectTemporalMarkers(in: text))
        organizations.append(contentsOf: detectOrganizations(in: text))

        for term in detectEnvironmentTokens(in: text) {
            environments.append(term)
        }

        return EntityAnalysis(
            persons: orderedUnique(persons),
            projects: orderedUnique(projects),
            environments: orderedUnique(environments.map { $0.lowercased() }),
            technicalTerms: orderedUnique(technicalTerms),
            temporalMarkers: orderedUnique(temporalMarkers),
            organizations: orderedUnique(organizations)
        )
    }

    private func detectPersons(in text: String) -> [String] {
        var persons: [String] = []

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let range = text.startIndex..<text.endIndex

        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, tokenRange in
            guard tag == .personalName else { return true }
            let candidate = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidPerson(candidate) {
                persons.append(candidate)
            }
            return true
        }

        let informalPatterns = [
            "\\byou\\s+as\\s+([A-Za-z][A-Za-z0-9_]{1,})",
            "\\b(?:my|our)\\s+([A-Za-z][A-Za-z0-9_]{1,})",
            "\\btell\\s+([A-Za-z][A-Za-z0-9_]{1,})",
            "\\b([A-Za-z][A-Za-z0-9_]{1,})\\s+is\\s+(?:working|handling|owning|reviewing)"
        ]

        for pattern in informalPatterns {
            persons.append(contentsOf: captureGroup(pattern: pattern, in: text, options: [.caseInsensitive]))
        }

        if text.lowercased().contains("my boss") {
            persons.append("my boss")
        }

        return persons.filter { isValidPerson($0) }
    }

    private func detectProjectsAndEnvironments(in text: String) -> (projects: [String], environments: [String]) {
        var projects: [String] = []
        var environments: [String] = []

        if let quotedRegex = try? NSRegularExpression(pattern: "'([^']+)'|\"([^\"]+)\"") {
            let range = NSRange(text.startIndex..., in: text)
            for match in quotedRegex.matches(in: text, range: range) {
                if let r1 = Range(match.range(at: 1), in: text), !r1.isEmpty {
                    projects.append(String(text[r1]))
                } else if let r2 = Range(match.range(at: 2), in: text), !r2.isEmpty {
                    projects.append(String(text[r2]))
                }
            }
        }

        let prepositionPattern = "\\b(?:on|in|for|within)\\s+(?:the\\s+|a\\s+|an\\s+)?([A-Za-z][A-Za-z0-9]*(?:[\\s-][A-Za-z0-9]+){0,3})"
        for phrase in captureGroup(pattern: prepositionPattern, in: text, options: [.caseInsensitive]) {
            let normalized = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            if environmentTerms.contains(normalized.lowercased()) {
                environments.append(normalized.lowercased())
            } else {
                projects.append(normalized)
            }
        }

        if let camelRegex = try? NSRegularExpression(pattern: "\\b[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+\\b") {
            let range = NSRange(text.startIndex..., in: text)
            for match in camelRegex.matches(in: text, range: range) {
                if let r = Range(match.range, in: text) {
                    projects.append(String(text[r]))
                }
            }
        }

        if let hyphenRegex = try? NSRegularExpression(pattern: "\\b[A-Za-z0-9]+-[A-Za-z0-9-]+\\b") {
            let range = NSRange(text.startIndex..., in: text)
            for match in hyphenRegex.matches(in: text, range: range) {
                if let r = Range(match.range, in: text) {
                    projects.append(String(text[r]))
                }
            }
        }

        let compoundPattern = "\\b([A-Za-z][A-Za-z0-9_-]{2,})\\s+(?:doesn't|doesnt|isn't|isnt|fails|crashes|breaks|trigger|triggers)"
        for token in captureGroup(pattern: compoundPattern, in: text, options: [.caseInsensitive]) {
            if !environmentTerms.contains(token.lowercased()) {
                projects.append(token)
            }
        }

        return (projects, environments)
    }

    private func detectEnvironmentTokens(in text: String) -> [String] {
        let words = text
            .lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }

        return words.filter { environmentTerms.contains($0) }
    }

    private func detectTechnicalTerms(in text: String, knownProjects: [String], knownEnvironments: [String]) -> [String] {
        let projectSet = Set(knownProjects.map { normalizeToken($0) })
        let envSet = Set(knownEnvironments.map { normalizeToken($0) })

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let range = text.startIndex..<text.endIndex

        var terms: [String] = []

        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            guard let tag else { return true }
            guard tag == .noun || tag == .otherWord else { return true }

            let token = String(text[tokenRange])
            let normalized = normalizeToken(token)
            if normalized.count < 3 { return true }
            if commonWords.contains(normalized) { return true }
            if envSet.contains(normalized) { return true }
            if personStopwords.contains(normalized) { return true }

            let looksTechnical = token.contains("_") || token.contains("-") || token.contains("/") || token.contains(".") ||
                token.rangeOfCharacter(from: .decimalDigits) != nil || containsCamelCase(token) || projectSet.contains(normalized)

            if looksTechnical || !isPlainDictionaryWord(normalized) {
                terms.append(normalized)
            }

            return true
        }

        return terms
    }

    private func detectTemporalMarkers(in text: String) -> [String] {
        let patterns = [
            "\\bsince\\s+\\d{1,2}(?::\\d{2})?\\s*(?:am|pm)?\\b",
            "\\bin\\s+the\\s+last\\s+\\w+\\b",
            "\\blast\\s+\\w+\\b",
            "\\byesterday\\b",
            "\\btoday\\b",
            "\\btonight\\b",
            "\\b\\d+\\s+(?:minutes?|hours?|days?|weeks?)\\s+ago\\b"
        ]

        var markers: [String] = []
        for pattern in patterns {
            markers.append(contentsOf: captureMatches(pattern: pattern, in: text, options: [.caseInsensitive]))
        }

        return markers
    }

    private func detectOrganizations(in text: String) -> [String] {
        var organizations: [String] = []

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let range = text.startIndex..<text.endIndex

        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, tokenRange in
            guard tag == .organizationName else { return true }
            organizations.append(String(text[tokenRange]))
            return true
        }

        let orgPatterns = [
            "\\b(?:the\\s+)?([A-Za-z][A-Za-z0-9]*(?:\\s+[A-Za-z][A-Za-z0-9]*){0,2})\\s+(?:team|group|department|org|organization|inc|corp|llc)\\b",
            "\\bat\\s+([A-Za-z][A-Za-z0-9_-]{2,})\\b"
        ]

        for pattern in orgPatterns {
            organizations.append(contentsOf: captureGroup(pattern: pattern, in: text, options: [.caseInsensitive]))
        }

        return organizations
    }

    private func captureMatches(pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r])
        }
    }

    private func captureGroup(pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..., in: text)

        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                ordered.append(trimmed)
            }
        }

        return ordered
    }

    private func normalizeToken(_ token: String) -> String {
        token
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
    }

    private func containsCamelCase(_ token: String) -> Bool {
        let hasLower = token.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasUpperAfterFirst = token.dropFirst().rangeOfCharacter(from: .uppercaseLetters) != nil
        return hasLower && hasUpperAfterFirst
    }

    private func isPlainDictionaryWord(_ token: String) -> Bool {
        token.rangeOfCharacter(from: .decimalDigits) == nil && !token.contains("_") && !token.contains("-") && !token.contains("/") && !token.contains(".")
    }

    private func isValidPerson(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard trimmed.count >= 2 else { return false }
        let lower = trimmed.lowercased()
        guard !personStopwords.contains(lower) else { return false }
        guard !environmentTerms.contains(lower) else { return false }
        return lower.range(of: "[^a-z0-9\\s_]", options: .regularExpression) == nil
    }
}
