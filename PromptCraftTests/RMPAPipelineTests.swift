import XCTest
@testable import PromptCraft

final class RMPAPipelineTests: XCTestCase {

    func testIntentDecomposerFrustratedInput() {
        let analysis = IntentDecomposer.shared.analyze("why the fuck shipcold doesn't trigger in my local???!!!!")

        XCTAssertEqual(analysis.intentCount, 1)
        XCTAssertEqual(analysis.urgencyLevel, 3)
        XCTAssertTrue(analysis.cleanedInput.contains("shipcold"))
        XCTAssertTrue(analysis.cleanedInput.contains("trigger"))
        XCTAssertTrue(analysis.cleanedInput.contains("local"))
    }

    func testEntityExtractorInformalInput() {
        let analysis = EntityExtractor.shared.analyze("you as clawd working on the new dashboard within vps")

        XCTAssertTrue(analysis.persons.map { $0.lowercased() }.contains("clawd"))
        XCTAssertTrue(analysis.projects.map { $0.lowercased() }.contains(where: { $0.contains("dashboard") }))
        XCTAssertTrue(analysis.environments.contains("vps"))
    }

    func testComplexityClassifierUsesIntentCountAndNotEmotion() {
        let raw = "why the fuck shipcold doesn't trigger in my local???!!!!"
        let intent = IntentDecomposer.shared.analyze(raw)
        let entities = EntityExtractor.shared.analyze(raw)

        let result = ComplexityClassifier.shared.classify(
            intentAnalysis: intent,
            entityAnalysis: entities,
            contextMatches: [],
            totalContextEntries: 0,
            verbosity: .concise
        )

        XCTAssertEqual(intent.intentCount, 1)
        XCTAssertEqual(result.tier, .trivial)
        XCTAssertLessThanOrEqual(result.maxOutputWords, 50)
    }

    func testPostProcessorStripsTier1FormattingAndMetaLeak() {
        let input = "## Context\n1. **Here is your optimized prompt**\n2. Fix the login bug\n- Validate retries"

        let result = PostProcessor.shared.process(
            outputText: input,
            tier: .trivial,
            maxOutputWords: 40
        )

        XCTAssertFalse(result.cleanedOutput.contains("##"))
        XCTAssertFalse(result.cleanedOutput.contains("**"))
        XCTAssertFalse(result.cleanedOutput.lowercased().contains("optimized prompt"))
        XCTAssertTrue(result.formattingStripped)
    }

    func testDetailedVerbosityUsesTier3ForSingleIntentSimpleInput() {
        let raw = "fix the typo in readme"
        let intent = IntentDecomposer.shared.analyze(raw)
        let entities = EntityExtractor.shared.analyze(raw)

        let result = ComplexityClassifier.shared.classify(
            intentAnalysis: intent,
            entityAnalysis: entities,
            contextMatches: [],
            totalContextEntries: 0,
            verbosity: .detailed
        )

        XCTAssertEqual(result.tier, .moderate)
        XCTAssertGreaterThanOrEqual(result.maxOutputWords, 150)
    }

    func testDetailedVerbosityUsesTier4ForMultiIntentInput() {
        let raw = "fix login bug and add retries"
        let intent = IntentDecomposer.shared.analyze(raw)
        let entities = EntityExtractor.shared.analyze(raw)

        let result = ComplexityClassifier.shared.classify(
            intentAnalysis: intent,
            entityAnalysis: entities,
            contextMatches: [],
            totalContextEntries: 0,
            verbosity: .detailed
        )

        XCTAssertEqual(result.tier, .complex)
    }

    func testConciseVerbosityCapsTierAtSimple() {
        let raw = "design auth service and migrate database and add runbook and add rollback plan and add monitoring"
        let intent = IntentDecomposer.shared.analyze(raw)
        let entities = EntityExtractor.shared.analyze(raw)

        let result = ComplexityClassifier.shared.classify(
            intentAnalysis: intent,
            entityAnalysis: entities,
            contextMatches: [],
            totalContextEntries: 0,
            verbosity: .concise
        )

        XCTAssertLessThanOrEqual(result.tier.tierNumber, 2)
        XCTAssertLessThanOrEqual(result.maxOutputWords, 100)
    }
}
