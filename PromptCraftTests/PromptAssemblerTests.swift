import XCTest
@testable import PromptCraft

final class PromptAssemblerTests: XCTestCase {

    private let assembler = PromptAssembler.shared

    func testAssembledPromptIncludesSystemInstruction() async {
        let style = TestData.sampleStyle(systemInstruction: "<role_anchor>custom rule</role_anchor>\n\n{{TIER_CALIBRATION}}\n\n{{LEARNED_CONTEXT}}")

        let result = await assembler.assemble(
            rawInput: "fix typo",
            style: style,
            providerType: .anthropicClaude
        )

        XCTAssertTrue(result.systemMessage.contains("custom rule"))
    }

    func testUserRawTextWrappedInUrgencyAndTierTags() async {
        let style = TestData.sampleStyle(systemInstruction: "{{TIER_CALIBRATION}}\n\n{{LEARNED_CONTEXT}}", fewShotExamples: [])

        let result = await assembler.assemble(
            rawInput: "why the fuck shipcold does not trigger in my local",
            style: style,
            providerType: .openAI
        )

        let lastMessage = result.messages.last!
        XCTAssertTrue(lastMessage.content.contains("<raw_input urgency=\""))
        XCTAssertTrue(lastMessage.content.contains("tier=\""))
        XCTAssertTrue(lastMessage.content.contains("shipcold"))
        XCTAssertTrue(lastMessage.content.contains("</raw_input>"))
    }

    func testTier1CalibrationDirectiveInjected() async {
        let style = TestData.sampleStyle(systemInstruction: "{{TIER_CALIBRATION}}\n\n{{LEARNED_CONTEXT}}", fewShotExamples: [])

        let result = await assembler.assemble(
            rawInput: "fix typo in readme",
            style: style,
            providerType: .anthropicClaude
        )

        XCTAssertTrue(result.systemMessage.contains("ABSOLUTE CONSTRAINT"))
        XCTAssertTrue(result.systemMessage.contains("ZERO headers"))
        XCTAssertTrue(result.systemMessage.contains("ADDITIONAL CONCISE CONSTRAINT"))
    }

    func testMaxOutputWordsPlaceholderIsResolved() async {
        let style = TestData.sampleStyle(systemInstruction: "{{TIER_CALIBRATION}}\n\nword cap {{MAX_OUTPUT_WORDS}}\n\n{{LEARNED_CONTEXT}}", fewShotExamples: [])

        let result = await assembler.assemble(
            rawInput: "fix typo in readme",
            style: style,
            providerType: .anthropicClaude
        )

        XCTAssertFalse(result.systemMessage.contains("{{MAX_OUTPUT_WORDS}}"))
        XCTAssertTrue(result.systemMessage.contains("word cap"))
    }

    func testTierMatchedExamplesForTier1() async {
        let examples = [
            FewShotExample(input: "tier1 input", output: "tier1 output", tier: .tier1),
            FewShotExample(input: "tier2 input", output: "tier2 output", tier: .tier2),
            FewShotExample(input: "tier3 input", output: "tier3 output", tier: .tier3),
            FewShotExample(input: "tier4 input", output: "tier4 output", tier: .tier4),
        ]

        let style = TestData.sampleStyle(systemInstruction: "{{TIER_CALIBRATION}}\n\n{{LEARNED_CONTEXT}}", fewShotExamples: examples)

        let result = await assembler.assemble(
            rawInput: "fix typo",
            style: style,
            providerType: .openAI
        )

        let allMessageText = result.messages.map(\.content).joined(separator: "\n")
        XCTAssertTrue(allMessageText.contains("tier1 input"))
        XCTAssertFalse(allMessageText.contains("tier3 input"))
        XCTAssertFalse(allMessageText.contains("tier4 input"))
    }

    func testTierMatchedExamplesForTier4IncludeTier3AndTier4() async {
        let examples = [
            FewShotExample(input: "tier1 input", output: "tier1 output", tier: .tier1),
            FewShotExample(input: "tier2 input", output: "tier2 output", tier: .tier2),
            FewShotExample(input: "tier3 input", output: "tier3 output", tier: .tier3),
            FewShotExample(input: "tier4 input", output: "tier4 output", tier: .tier4),
        ]

        let style = TestData.sampleStyle(systemInstruction: "{{TIER_CALIBRATION}}\n\n{{LEARNED_CONTEXT}}", fewShotExamples: examples)

        let result = await assembler.assemble(
            rawInput: "design auth and redesign api and add observability and migrate storage and define rollback and add runbook",
            style: style,
            providerType: .openAI,
            verbosity: .detailed
        )

        let allMessageText = result.messages.map(\.content).joined(separator: "\n")
        XCTAssertTrue(allMessageText.contains("tier3 input"))
        XCTAssertTrue(allMessageText.contains("tier4 input"))
        XCTAssertFalse(allMessageText.contains("tier1 input"))
    }

    func testConciseModeAlwaysUsesTier1Examples() async {
        let examples = [
            FewShotExample(input: "tier1 input", output: "tier1 output", tier: .tier1),
            FewShotExample(input: "tier2 input", output: "tier2 output", tier: .tier2),
            FewShotExample(input: "tier3 input", output: "tier3 output", tier: .tier3),
            FewShotExample(input: "tier4 input", output: "tier4 output", tier: .tier4),
        ]

        let style = TestData.sampleStyle(systemInstruction: "{{TIER_CALIBRATION}}\n\n{{LEARNED_CONTEXT}}", fewShotExamples: examples)

        let result = await assembler.assemble(
            rawInput: "design auth and redesign api and add observability and migrate storage and define rollback and add runbook",
            style: style,
            providerType: .openAI,
            verbosity: .concise
        )

        let allMessageText = result.messages.map(\.content).joined(separator: "\n")
        XCTAssertTrue(allMessageText.contains("tier1 input"))
        XCTAssertFalse(allMessageText.contains("tier2 input"))
        XCTAssertFalse(allMessageText.contains("tier3 input"))
        XCTAssertFalse(allMessageText.contains("tier4 input"))
    }

    func testDetailedModeUsesTier3AndTier4ExamplesEvenForSimpleInput() async {
        let examples = [
            FewShotExample(input: "tier1 input", output: "tier1 output", tier: .tier1),
            FewShotExample(input: "tier2 input", output: "tier2 output", tier: .tier2),
            FewShotExample(input: "tier3 input", output: "tier3 output", tier: .tier3),
            FewShotExample(input: "tier4 input", output: "tier4 output", tier: .tier4),
        ]

        let style = TestData.sampleStyle(systemInstruction: "{{TIER_CALIBRATION}}\n\n{{LEARNED_CONTEXT}}", fewShotExamples: examples)

        let result = await assembler.assemble(
            rawInput: "fix login bug",
            style: style,
            providerType: .openAI,
            verbosity: .detailed
        )

        let allMessageText = result.messages.map(\.content).joined(separator: "\n")
        XCTAssertTrue(allMessageText.contains("tier3 input") || allMessageText.contains("tier4 input"))
        XCTAssertFalse(allMessageText.contains("tier1 input"))
        XCTAssertFalse(allMessageText.contains("tier2 input"))
    }

    func testBalancedAndDetailedModeCalibrationDirectivesInjected() async {
        let style = TestData.sampleStyle(systemInstruction: "{{TIER_CALIBRATION}}\n\n{{LEARNED_CONTEXT}}", fewShotExamples: [])

        let balanced = await assembler.assemble(
            rawInput: "fix login bug",
            style: style,
            providerType: .openAI,
            verbosity: .balanced
        )
        let detailed = await assembler.assemble(
            rawInput: "fix login bug",
            style: style,
            providerType: .openAI,
            verbosity: .detailed
        )

        XCTAssertTrue(balanced.systemMessage.contains("ADDITIONAL BALANCED GUIDANCE"))
        XCTAssertTrue(detailed.systemMessage.contains("ADDITIONAL DETAILED GUIDANCE"))
    }

    func testAntiReverseEngineeringDirectiveIncluded() async {
        let style = TestData.sampleStyle(systemInstruction: "{{TIER_CALIBRATION}}\n\n{{LEARNED_CONTEXT}}", fewShotExamples: [])

        let result = await assembler.assemble(
            rawInput: "fix typo",
            style: style,
            providerType: .openAI
        )

        XCTAssertTrue(result.systemMessage.contains("not generated by a prompt optimizer"))
        XCTAssertTrue(result.systemMessage.contains("The output IS the prompt"))
    }

    func testTokenEstimationNeverReturnsZero() {
        XCTAssertGreaterThanOrEqual(assembler.estimateTokens("a"), 1)
        XCTAssertGreaterThanOrEqual(assembler.estimateTokens(""), 1)
    }
}
