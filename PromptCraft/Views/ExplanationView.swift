import SwiftUI

struct ExplanationView: View {
    let explanation: PromptExplanation

    private let monoFont = Font.system(.caption, design: .monospaced)
    private let labelColor = Color.secondary.opacity(0.7)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Section 1 — CLASSIFICATION
            line("CLASSIFICATION", "Tier \(explanation.detectedTier.tierNumber) (\(explanation.detectedTier.rawValue)) — \(explanation.tierReason)")

            // Section 2 — INTENT DECOMPOSITION
            if explanation.intents.isEmpty {
                line("INTENTS", "none detected")
            } else {
                let intentList = explanation.intents.map { "\($0.verb) → \($0.object)" }.joined(separator: ", ")
                line("INTENTS", "[\(explanation.intentCount)] \(intentList)")
            }

            // Section 3 — ENTITIES
            line("ENTITIES", explanation.entitySummary)

            // Section 4 — CONTEXT ENGINE
            line("CONTEXT", "\(explanation.contextEntriesUsed) context entr\(explanation.contextEntriesUsed == 1 ? "y" : "ies") injected (boosted: \(explanation.contextBoosted ? "yes" : "no"))")

            // Section 5 — CALIBRATION
            line("CALIBRATION", "Max output: \(explanation.maxOutputWords) words | Verbosity: \(explanation.verbosityMode.rawValue) | Few-shot examples: \(explanation.fewShotExamplesIncluded)")

            // Section 6 — POST-PROCESSING
            if !explanation.postProcessActions.isEmpty {
                let actions = explanation.postProcessActions.joined(separator: ", ")
                line("POST-PROCESS", actions)
            }

            // Emotional markers & urgency (if present)
            if !explanation.emotionalMarkersDetected.isEmpty || explanation.urgencyLevel > 0 {
                let markers = explanation.emotionalMarkersDetected.isEmpty ? "none" : explanation.emotionalMarkersDetected.joined(separator: ", ")
                line("SIGNALS", "Urgency: \(explanation.urgencyLevel) | Emotional markers: \(markers)")
            }

            // Section 7 — PIPELINE
            line("PIPELINE", "Provider: \(explanation.providerUsed) | Model: \(explanation.modelUsed) | Estimated tokens: \(explanation.estimatedTokenCount)")
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
        )
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(label): ")
                .font(monoFont)
                .foregroundStyle(labelColor)
            Text(value)
                .font(monoFont)
                .foregroundStyle(.secondary)
        }
    }
}
