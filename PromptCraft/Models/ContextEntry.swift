import Foundation

/// Represents a stored context entry from a past optimization,
/// used by the local RAG system to inform future optimizations.
struct ContextEntry: Identifiable, Equatable {
    let id: UUID
    let text: String           // Raw user input text only
    let outputText: String     // Raw LLM output text only
    let embedding: [Float]
    let persons: [String]
    let projects: [String]
    let environments: [String]
    let technicalTerms: [String]
    let sourceType: SourceType
    let sourcePromptID: UUID?
    let clusterID: UUID?
    let createdAt: Date
    var lastAccessedAt: Date
    var accessCount: Int
    let tokenCount: Int

    enum SourceType: String {
        case optimization
        case input
        case output
    }

    init(
        id: UUID = UUID(),
        text: String,
        outputText: String = "",
        embedding: [Float],
        persons: [String] = [],
        projects: [String] = [],
        environments: [String] = [],
        technicalTerms: [String] = [],
        sourceType: SourceType,
        sourcePromptID: UUID? = nil,
        clusterID: UUID? = nil,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date(),
        accessCount: Int = 0,
        tokenCount: Int = 0
    ) {
        self.id = id
        self.text = text
        self.outputText = outputText
        self.embedding = embedding
        self.persons = persons
        self.projects = projects
        self.environments = environments
        self.technicalTerms = technicalTerms
        self.sourceType = sourceType
        self.sourcePromptID = sourcePromptID
        self.clusterID = clusterID
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.accessCount = accessCount
        self.tokenCount = tokenCount
    }
}

/// A search result from context retrieval, including similarity score.
struct ContextSearchResult: Identifiable {
    let id: UUID
    let entry: ContextEntry
    let similarity: Float
    let boostedScore: Float
}
