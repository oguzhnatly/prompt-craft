import XCTest
@testable import PromptCraft

final class PromptStyleTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    // MARK: - Codable Roundtrip

    func testCodableRoundtrip_fullyPopulatedStyle() throws {
        let style = TestData.sampleStyle(
            enforcedPrefix: "BEGIN:",
            enforcedSuffix: "END.",
            targetModelHint: .claude
        )

        let data = try encoder.encode(style)
        let decoded = try decoder.decode(PromptStyle.self, from: data)

        XCTAssertEqual(decoded.id, style.id)
        XCTAssertEqual(decoded.displayName, style.displayName)
        XCTAssertEqual(decoded.shortDescription, style.shortDescription)
        XCTAssertEqual(decoded.category, style.category)
        XCTAssertEqual(decoded.iconName, style.iconName)
        XCTAssertEqual(decoded.sortOrder, style.sortOrder)
        XCTAssertEqual(decoded.isBuiltIn, style.isBuiltIn)
        XCTAssertEqual(decoded.isEnabled, style.isEnabled)
        XCTAssertEqual(decoded.systemInstruction, style.systemInstruction)
        XCTAssertEqual(decoded.outputStructure, style.outputStructure)
        XCTAssertEqual(decoded.toneDescriptor, style.toneDescriptor)
        XCTAssertEqual(decoded.fewShotExamples, style.fewShotExamples)
        XCTAssertEqual(decoded.enforcedPrefix, style.enforcedPrefix)
        XCTAssertEqual(decoded.enforcedSuffix, style.enforcedSuffix)
        XCTAssertEqual(decoded.targetModelHint, style.targetModelHint)
    }

    func testAllDefaultStylesDecodeCorrectly() throws {
        for style in DefaultStyles.all {
            let data = try encoder.encode(style)
            let decoded = try decoder.decode(PromptStyle.self, from: data)

            // Compare all fields except dates (Date roundtrip through JSON can lose
            // sub-second precision due to floating-point arithmetic).
            XCTAssertEqual(decoded.id, style.id, "ID mismatch for '\(style.displayName)'")
            XCTAssertEqual(decoded.displayName, style.displayName)
            XCTAssertEqual(decoded.shortDescription, style.shortDescription)
            XCTAssertEqual(decoded.category, style.category)
            XCTAssertEqual(decoded.iconName, style.iconName)
            XCTAssertEqual(decoded.sortOrder, style.sortOrder)
            XCTAssertEqual(decoded.isBuiltIn, style.isBuiltIn)
            XCTAssertEqual(decoded.isEnabled, style.isEnabled)
            XCTAssertEqual(decoded.systemInstruction, style.systemInstruction)
            XCTAssertEqual(decoded.outputStructure, style.outputStructure)
            XCTAssertEqual(decoded.toneDescriptor, style.toneDescriptor)
            XCTAssertEqual(decoded.fewShotExamples, style.fewShotExamples)
            XCTAssertEqual(decoded.enforcedPrefix, style.enforcedPrefix)
            XCTAssertEqual(decoded.enforcedSuffix, style.enforcedSuffix)
            XCTAssertEqual(decoded.targetModelHint, style.targetModelHint)

            // Dates: check within 1-second tolerance
            XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, style.createdAt.timeIntervalSince1970, accuracy: 1.0)
            XCTAssertEqual(decoded.modifiedAt.timeIntervalSince1970, style.modifiedAt.timeIntervalSince1970, accuracy: 1.0)
        }
    }

    func testFewShotExamplesPreservedThroughSerialization() throws {
        let examples = [
            FewShotExample(input: "input one", output: "output one"),
            FewShotExample(input: "input two", output: "output two"),
            FewShotExample(input: "input three", output: "output three"),
        ]
        let style = TestData.sampleStyle(fewShotExamples: examples)

        let data = try encoder.encode(style)
        let decoded = try decoder.decode(PromptStyle.self, from: data)

        XCTAssertEqual(decoded.fewShotExamples.count, 3)
        XCTAssertEqual(decoded.fewShotExamples, examples)
    }

    func testStyleWithMissingOptionalFieldsDecodesWithoutError() throws {
        // Create JSON without enforcedPrefix and enforcedSuffix
        let style = TestData.sampleStyle(enforcedPrefix: nil, enforcedSuffix: nil)
        let data = try encoder.encode(style)
        let decoded = try decoder.decode(PromptStyle.self, from: data)

        XCTAssertNil(decoded.enforcedPrefix)
        XCTAssertNil(decoded.enforcedSuffix)
        XCTAssertEqual(decoded.displayName, style.displayName)
    }

    // MARK: - DefaultStyles

    func testDefaultStylesHaveUniqueIDs() {
        let ids = DefaultStyles.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Default styles should have unique IDs")
    }

    func testDefaultStylesAllMarkedAsBuiltIn() {
        for style in DefaultStyles.all {
            XCTAssertTrue(style.isBuiltIn, "Default style '\(style.displayName)' should be built-in")
        }
    }

    func testDefaultStylesAllEnabled() {
        for style in DefaultStyles.all {
            XCTAssertTrue(style.isEnabled, "Default style '\(style.displayName)' should be enabled")
        }
    }

    func testDefaultStylesHaveNonEmptySystemInstructions() {
        for style in DefaultStyles.all {
            XCTAssertFalse(style.systemInstruction.isEmpty, "Default style '\(style.displayName)' should have a system instruction")
        }
    }

    func testDefaultStylesCount() {
        XCTAssertEqual(DefaultStyles.all.count, 7)
    }

    // MARK: - PromptHistoryEntry Codable

    func testHistoryEntryRoundtrip() throws {
        let entry = TestData.sampleHistoryEntry(isFavorited: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(PromptHistoryEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.inputText, entry.inputText)
        XCTAssertEqual(decoded.outputText, entry.outputText)
        XCTAssertEqual(decoded.styleID, entry.styleID)
        XCTAssertEqual(decoded.providerName, entry.providerName)
        XCTAssertEqual(decoded.modelName, entry.modelName)
        XCTAssertEqual(decoded.durationMilliseconds, entry.durationMilliseconds)
        XCTAssertEqual(decoded.isFavorited, true)
    }

    // MARK: - AppConfiguration Codable

    func testAppConfigurationRoundtrip() throws {
        let config = AppConfiguration.default

        let data = try encoder.encode(config)
        let decoded = try decoder.decode(AppConfiguration.self, from: data)

        XCTAssertEqual(decoded.selectedProvider, config.selectedProvider)
        XCTAssertEqual(decoded.temperature, config.temperature)
        XCTAssertEqual(decoded.maxOutputTokens, config.maxOutputTokens)
        XCTAssertEqual(decoded.autoCopyToClipboard, config.autoCopyToClipboard)
        XCTAssertEqual(decoded.historyLimit, config.historyLimit)
    }

    func testAppConfigurationDecodesWithMissingNewFields() throws {
        // Simulate old config without newer optional fields
        let config = AppConfiguration.default
        let data = try encoder.encode(config)

        // Remove newer keys by re-encoding as dictionary and stripping
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "clipboardCaptureEnabled")
        dict.removeValue(forKey: "autoCaptureSelectedText")
        dict.removeValue(forKey: "quickOptimizeEnabled")
        dict.removeValue(forKey: "quickOptimizeAutoClose")
        dict.removeValue(forKey: "quickOptimizeAutoCloseDelay")
        dict.removeValue(forKey: "showCharacterCount")

        let strippedData = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try decoder.decode(AppConfiguration.self, from: strippedData)

        // Should use defaults for missing fields
        XCTAssertTrue(decoded.clipboardCaptureEnabled)
        XCTAssertFalse(decoded.autoCaptureSelectedText)
        XCTAssertFalse(decoded.quickOptimizeEnabled)
        XCTAssertFalse(decoded.quickOptimizeAutoClose)
        XCTAssertEqual(decoded.quickOptimizeAutoCloseDelay, 2.5)
        XCTAssertTrue(decoded.showCharacterCount)
    }

    // MARK: - StyleCategory & Enums

    func testStyleCategoryAllCases() {
        XCTAssertEqual(StyleCategory.allCases.count, 6)
    }

    func testTargetModelHintAllCases() {
        XCTAssertEqual(TargetModelHint.allCases.count, 4)
    }

    func testLLMProviderAllCases() {
        XCTAssertEqual(LLMProvider.allCases.count, 6)
    }
}
