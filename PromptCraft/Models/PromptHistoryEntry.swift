import Foundation

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

    init(
        id: UUID = UUID(),
        inputText: String,
        outputText: String,
        styleID: UUID,
        timestamp: Date = Date(),
        providerName: String,
        modelName: String,
        durationMilliseconds: Int,
        isFavorited: Bool = false
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
    }
}
