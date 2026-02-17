import Foundation

enum PromptSourceType: String, Codable, Equatable {
    case manual
    case watchFolder
    case inline
    case contextMenu
    case api
}

struct PromptHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let inputText: String
    let outputText: String
    let styleID: UUID
    let timestamp: Date
    let providerName: String
    let modelName: String
    let durationMilliseconds: Int
    var isFavorited: Bool
    let sourceType: PromptSourceType
    var exportedAsSystemPrompt: Bool

    init(
        id: UUID = UUID(),
        inputText: String,
        outputText: String,
        styleID: UUID,
        timestamp: Date = Date(),
        providerName: String,
        modelName: String,
        durationMilliseconds: Int,
        isFavorited: Bool = false,
        sourceType: PromptSourceType = .manual,
        exportedAsSystemPrompt: Bool = false
    ) {
        self.id = id
        self.inputText = inputText
        self.outputText = outputText
        self.styleID = styleID
        self.timestamp = timestamp
        self.providerName = providerName
        self.modelName = modelName
        self.durationMilliseconds = durationMilliseconds
        self.isFavorited = isFavorited
        self.sourceType = sourceType
        self.exportedAsSystemPrompt = exportedAsSystemPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        inputText = try container.decode(String.self, forKey: .inputText)
        outputText = try container.decode(String.self, forKey: .outputText)
        styleID = try container.decode(UUID.self, forKey: .styleID)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        providerName = try container.decode(String.self, forKey: .providerName)
        modelName = try container.decode(String.self, forKey: .modelName)
        durationMilliseconds = try container.decode(Int.self, forKey: .durationMilliseconds)
        isFavorited = try container.decode(Bool.self, forKey: .isFavorited)
        sourceType = try container.decodeIfPresent(PromptSourceType.self, forKey: .sourceType) ?? .manual
        exportedAsSystemPrompt = try container.decodeIfPresent(Bool.self, forKey: .exportedAsSystemPrompt) ?? false
    }
}
