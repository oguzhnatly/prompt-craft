import XCTest
@testable import PromptCraft

final class PromptAssemblerTests: XCTestCase {

    private let assembler = PromptAssembler.shared

    // MARK: - System Instruction Inclusion

    func testAssembledPromptIncludesSystemInstruction() {
        let style = TestData.sampleStyle(
            systemInstruction: "You must rewrite every prompt for clarity."
        )

        let result = assembler.assemble(
            rawInput: "make my code better",
            style: style,
            providerType: .anthropicClaude
        )

        XCTAssertTrue(
            result.systemMessage.contains("You must rewrite every prompt for clarity."),
            "System message should contain the style's system instruction"
        )
    }

    // MARK: - Few-Shot Examples

    func testFewShotExamplesIncludedAsUserAssistantPairs() {
        let examples = [
            FewShotExample(input: "fix bugs", output: "Please identify and fix all bugs in the following code."),
            FewShotExample(input: "add tests", output: "Write comprehensive unit tests for the following module."),
        ]
        let style = TestData.sampleStyle(fewShotExamples: examples)

        let result = assembler.assemble(
            rawInput: "help me",
            style: style,
            providerType: .anthropicClaude
        )

        // Few-shot examples come as pairs before the user message
        // Last message should be the user's raw input
        let messages = result.messages
        XCTAssertGreaterThanOrEqual(messages.count, 5) // 2 pairs + 1 user

        // First pair
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertTrue(messages[0].content.contains("fix bugs"))
        XCTAssertEqual(messages[1].role, .assistant)
        XCTAssertTrue(messages[1].content.contains("Please identify and fix all bugs"))

        // Second pair
        XCTAssertEqual(messages[2].role, .user)
        XCTAssertTrue(messages[2].content.contains("add tests"))
        XCTAssertEqual(messages[3].role, .assistant)
        XCTAssertTrue(messages[3].content.contains("Write comprehensive unit tests"))

        // Final message is the user's raw input
        let lastMessage = messages.last!
        XCTAssertEqual(lastMessage.role, .user)
        XCTAssertTrue(lastMessage.content.contains("help me"))
    }

    // MARK: - User Message Wrapping

    func testUserRawTextWrappedInTags() {
        let style = TestData.sampleStyle(fewShotExamples: [])

        let result = assembler.assemble(
            rawInput: "explain quantum computing",
            style: style,
            providerType: .openAI
        )

        let lastMessage = result.messages.last!
        XCTAssertTrue(lastMessage.content.contains("<raw_prompt>"))
        XCTAssertTrue(lastMessage.content.contains("explain quantum computing"))
        XCTAssertTrue(lastMessage.content.contains("</raw_prompt>"))
    }

    // MARK: - Prefix and Suffix

    func testPrefixIncludedInSystemMessage() {
        let style = TestData.sampleStyle(
            fewShotExamples: [],
            enforcedPrefix: "IMPORTANT BEGINNING"
        )

        let result = assembler.assemble(
            rawInput: "test input",
            style: style,
            providerType: .anthropicClaude
        )

        XCTAssertTrue(
            result.systemMessage.contains("IMPORTANT BEGINNING"),
            "System message should contain enforced prefix"
        )
    }

    func testSuffixIncludedInSystemMessage() {
        let style = TestData.sampleStyle(
            fewShotExamples: [],
            enforcedSuffix: "Always list your assumptions."
        )

        let result = assembler.assemble(
            rawInput: "test input",
            style: style,
            providerType: .anthropicClaude
        )

        XCTAssertTrue(
            result.systemMessage.contains("Always list your assumptions."),
            "System message should contain enforced suffix"
        )
    }

    // MARK: - Token Estimation

    func testTokenEstimationReasonableForEnglishText() {
        // Average English text: ~4 chars per token (OpenAI's tokenizer typically gives ~4-5)
        let text = "The quick brown fox jumps over the lazy dog. This is a sample sentence for testing token estimation accuracy."
        let estimatedTokens = assembler.estimateTokens(text)
        let charCount = text.count

        // Expected: charCount / 4 = ~27 tokens
        // Allow 20% tolerance
        let expected = Double(charCount) / 4.0
        let lower = expected * 0.8
        let upper = expected * 1.2

        XCTAssertGreaterThanOrEqual(Double(estimatedTokens), lower, "Token estimate too low")
        XCTAssertLessThanOrEqual(Double(estimatedTokens), upper, "Token estimate too high")
    }

    func testTokenEstimationNeverReturnsZero() {
        XCTAssertGreaterThanOrEqual(assembler.estimateTokens("a"), 1)
        XCTAssertGreaterThanOrEqual(assembler.estimateTokens(""), 1)
    }

    // MARK: - Few-Shot Truncation

    func testFewShotExamplesTruncatedWhenExceedingTokenLimit() {
        // Create many large examples
        let longOutput = String(repeating: "This is a very long output sentence. ", count: 100)
        let examples = (0..<10).map { i in
            FewShotExample(input: "Example input \(i)", output: longOutput)
        }
        let style = TestData.sampleStyle(fewShotExamples: examples)

        // Very small context limit forces truncation
        let result = assembler.assemble(
            rawInput: "test",
            style: style,
            providerType: .anthropicClaude,
            maxContextTokens: 2000
        )

        XCTAssertTrue(result.wasTruncated, "Should report truncation with small context limit")
        // Should have fewer than all 10 example pairs
        let exampleMessageCount = result.messages.count - 1 // minus the final user message
        XCTAssertLessThan(exampleMessageCount, 20, "Should include fewer than all 10 pairs (20 messages)")
    }

    func testNoTruncationWithSufficientTokens() {
        let examples = [
            FewShotExample(input: "short", output: "brief"),
        ]
        let style = TestData.sampleStyle(fewShotExamples: examples)

        let result = assembler.assemble(
            rawInput: "test",
            style: style,
            providerType: .anthropicClaude,
            maxContextTokens: 100_000
        )

        XCTAssertFalse(result.wasTruncated, "Should not truncate with large context limit")
    }

    // MARK: - Empty System Instruction

    func testAssemblyWithEmptySystemInstruction() {
        let style = TestData.sampleStyle(
            systemInstruction: "",
            fewShotExamples: []
        )

        let result = assembler.assemble(
            rawInput: "test input",
            style: style,
            providerType: .anthropicClaude
        )

        // Should still have a system message (the base role definition)
        XCTAssertFalse(result.systemMessage.isEmpty)
        // Should still have the user message
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertEqual(result.messages.last?.role, .user)
    }

    // MARK: - Very Long Input

    func testAssemblyWithVeryLongInput() {
        let longInput = String(repeating: "This is a test sentence. ", count: 2000)
        let style = TestData.sampleStyle(fewShotExamples: [])

        let result = assembler.assemble(
            rawInput: longInput,
            style: style,
            providerType: .openAI
        )

        XCTAssertTrue(result.messages.last!.content.contains(longInput))
        XCTAssertGreaterThan(result.estimatedTokenCount, 1000)
    }

    // MARK: - Provider-Specific Formatting

    func testClaudeProviderGetsXMLFormattingHint() {
        let style = TestData.sampleStyle(fewShotExamples: [])

        // Use complex tier so formatting hints are included
        let result = assembler.assemble(
            rawInput: "test",
            style: style,
            providerType: .anthropicClaude,
            complexityTier: .complex
        )

        XCTAssertTrue(result.systemMessage.contains("XML tags"))
    }

    func testOpenAIProviderGetsMarkdownFormattingHint() {
        let style = TestData.sampleStyle(fewShotExamples: [])

        // Use complex tier so formatting hints are included
        let result = assembler.assemble(
            rawInput: "test",
            style: style,
            providerType: .openAI,
            complexityTier: .complex
        )

        XCTAssertTrue(result.systemMessage.contains("markdown"))
    }

    // MARK: - Output Structure

    func testOutputStructureIncludedInSystemMessage() {
        let style = TestData.sampleStyle(
            outputStructure: ["Problem", "Solution", "Tests"],
            fewShotExamples: []
        )

        // Use complex tier so output structure is included
        let result = assembler.assemble(
            rawInput: "test",
            style: style,
            providerType: .anthropicClaude,
            complexityTier: .complex
        )

        XCTAssertTrue(result.systemMessage.contains("Problem"))
        XCTAssertTrue(result.systemMessage.contains("Solution"))
        XCTAssertTrue(result.systemMessage.contains("Tests"))
    }

    // MARK: - Tone Descriptor

    func testToneDescriptorIncludedInSystemMessage() {
        let style = TestData.sampleStyle(
            toneDescriptor: "formal and academic",
            fewShotExamples: []
        )

        let result = assembler.assemble(
            rawInput: "test",
            style: style,
            providerType: .openAI
        )

        XCTAssertTrue(result.systemMessage.contains("formal and academic"))
    }

    // MARK: - Calibration Directive Tests

    func testTier1CalibrationIncludesHardConstraint() {
        let style = TestData.sampleStyle(fewShotExamples: [])

        let result = assembler.assemble(
            rawInput: "fix the typo",
            style: style,
            providerType: .anthropicClaude,
            complexityTier: .trivial,
            maxOutputWords: 30
        )

        XCTAssertTrue(
            result.systemMessage.contains("HARD CONSTRAINT"),
            "Tier 1 calibration should include HARD CONSTRAINT"
        )
        XCTAssertTrue(
            result.systemMessage.contains("30"),
            "Tier 1 calibration should include the maxOutputWords value"
        )
        XCTAssertTrue(
            result.systemMessage.contains("1-2 sentences"),
            "Tier 1 should limit to 1-2 sentences"
        )
    }

    func testMaxOutputWordsFlowsThroughToSystemMessage() {
        let style = TestData.sampleStyle(fewShotExamples: [])

        let result = assembler.assemble(
            rawInput: "test input",
            style: style,
            providerType: .anthropicClaude,
            complexityTier: .simple,
            maxOutputWords: 120
        )

        XCTAssertTrue(
            result.systemMessage.contains("120"),
            "maxOutputWords should appear in the system message"
        )
        XCTAssertTrue(
            result.systemMessage.contains("HARD CONSTRAINT"),
            "Tier 2 should also have HARD CONSTRAINT"
        )
    }

    func testTier3UsesOutputGuidance() {
        let style = TestData.sampleStyle(fewShotExamples: [])

        let result = assembler.assemble(
            rawInput: "test",
            style: style,
            providerType: .anthropicClaude,
            complexityTier: .moderate,
            maxOutputWords: 300
        )

        XCTAssertTrue(
            result.systemMessage.contains("OUTPUT GUIDANCE"),
            "Tier 3 should use OUTPUT GUIDANCE, not HARD CONSTRAINT"
        )
        XCTAssertTrue(
            result.systemMessage.contains("300"),
            "Tier 3 should include word target"
        )
    }

    func testTier4UsesOutputGuidanceWithStructure() {
        let style = TestData.sampleStyle(fewShotExamples: [])

        let result = assembler.assemble(
            rawInput: "test",
            style: style,
            providerType: .anthropicClaude,
            complexityTier: .complex,
            maxOutputWords: 600
        )

        XCTAssertTrue(
            result.systemMessage.contains("OUTPUT GUIDANCE"),
            "Tier 4 should use OUTPUT GUIDANCE"
        )
        XCTAssertTrue(
            result.systemMessage.contains("full structured formatting"),
            "Tier 4 should mention full structured formatting"
        )
    }
}
