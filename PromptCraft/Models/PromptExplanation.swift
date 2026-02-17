import Foundation

struct PromptExplanation {
    let detectedTier: ComplexityTier
    let tierReason: String
    let intentCount: Int
    let intents: [Intent]
    let entitySummary: String
    let contextEntriesUsed: Int
    let contextBoosted: Bool
    let maxOutputWords: Int
    let verbosityMode: OutputVerbosity
    let fewShotExamplesIncluded: Int
    let emotionalMarkersDetected: [String]
    let urgencyLevel: Int
    let postProcessActions: [String]
    let estimatedTokenCount: Int
    let providerUsed: String
    let modelUsed: String
}
