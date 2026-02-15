import Foundation

// MARK: - Supporting Types

enum StyleCategory: String, Codable, CaseIterable {
    case technical
    case creative
    case business
    case research
    case communication
    case custom

    var displayName: String {
        switch self {
        case .technical: return "Technical"
        case .creative: return "Creative"
        case .business: return "Business"
        case .research: return "Research"
        case .communication: return "Communication"
        case .custom: return "Custom"
        }
    }
}

enum TargetModelHint: String, Codable, CaseIterable {
    case any
    case claude
    case chatgpt
    case gemini

    var displayName: String {
        switch self {
        case .any: return "Any"
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        }
    }
}

// MARK: - Style Export Envelope

struct StyleExportEnvelope: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let style: PromptStyle

    init(style: PromptStyle) {
        self.schemaVersion = Self.currentSchemaVersion
        self.exportedAt = Date()
        self.style = style
    }
}

struct FewShotExample: Codable, Equatable {
    let input: String
    let output: String
}

// MARK: - PromptStyle

struct PromptStyle: Codable, Identifiable, Equatable {
    let id: UUID
    var displayName: String
    var shortDescription: String
    var category: StyleCategory
    var iconName: String
    var sortOrder: Int
    var isBuiltIn: Bool
    var isEnabled: Bool
    var isInternal: Bool
    var createdAt: Date
    var modifiedAt: Date

    // Transformation recipe
    var systemInstruction: String
    var outputStructure: [String]
    var toneDescriptor: String
    var fewShotExamples: [FewShotExample]
    var enforcedPrefix: String?
    var enforcedSuffix: String?
    var targetModelHint: TargetModelHint

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        shortDescription = try container.decode(String.self, forKey: .shortDescription)
        category = try container.decode(StyleCategory.self, forKey: .category)
        iconName = try container.decode(String.self, forKey: .iconName)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        isInternal = try container.decodeIfPresent(Bool.self, forKey: .isInternal) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        systemInstruction = try container.decode(String.self, forKey: .systemInstruction)
        outputStructure = try container.decode([String].self, forKey: .outputStructure)
        toneDescriptor = try container.decode(String.self, forKey: .toneDescriptor)
        fewShotExamples = try container.decode([FewShotExample].self, forKey: .fewShotExamples)
        enforcedPrefix = try container.decodeIfPresent(String.self, forKey: .enforcedPrefix)
        enforcedSuffix = try container.decodeIfPresent(String.self, forKey: .enforcedSuffix)
        targetModelHint = try container.decode(TargetModelHint.self, forKey: .targetModelHint)
    }

    init(
        id: UUID = UUID(),
        displayName: String,
        shortDescription: String,
        category: StyleCategory,
        iconName: String,
        sortOrder: Int,
        isBuiltIn: Bool = false,
        isEnabled: Bool = true,
        isInternal: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        systemInstruction: String,
        outputStructure: [String] = [],
        toneDescriptor: String = "",
        fewShotExamples: [FewShotExample] = [],
        enforcedPrefix: String? = nil,
        enforcedSuffix: String? = nil,
        targetModelHint: TargetModelHint = .any
    ) {
        self.id = id
        self.displayName = displayName
        self.shortDescription = shortDescription
        self.category = category
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.isInternal = isInternal
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.systemInstruction = systemInstruction
        self.outputStructure = outputStructure
        self.toneDescriptor = toneDescriptor
        self.fewShotExamples = fewShotExamples
        self.enforcedPrefix = enforcedPrefix
        self.enforcedSuffix = enforcedSuffix
        self.targetModelHint = targetModelHint
    }
}
