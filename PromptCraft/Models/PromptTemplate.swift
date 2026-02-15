import Foundation

// MARK: - PromptTemplate

struct PromptTemplate: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var category: String
    var iconName: String
    var templateText: String
    var isBuiltIn: Bool
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        category: String = "General",
        iconName: String = "doc.text",
        templateText: String,
        isBuiltIn: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.iconName = iconName
        self.templateText = templateText
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Extract all {{placeholder}} names from the template text.
    var placeholders: [String] {
        let pattern = "\\{\\{([^}]+)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = templateText as NSString
        let matches = regex.matches(in: templateText, range: NSRange(location: 0, length: nsString.length))
        var seen = Set<String>()
        var result: [String] = []
        for match in matches {
            let name = nsString.substring(with: match.range(at: 1))
            if !seen.contains(name) {
                seen.insert(name)
                result.append(name)
            }
        }
        return result
    }

    /// Assemble the template by replacing placeholders with provided values.
    func assemble(values: [String: String]) -> String {
        var result = templateText
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }
}

// MARK: - Export Envelope

struct TemplateExportEnvelope: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let templates: [PromptTemplate]

    init(templates: [PromptTemplate]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.exportedAt = Date()
        self.templates = templates
    }
}
