import Combine
import XCTest
@testable import PromptCraft

final class ConfigurationServiceTests: XCTestCase {

    private var sut: ConfigurationService!
    private var testDefaults: UserDefaults!
    private var testKey: String!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        let suiteName = "com.promptcraft.test.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
        testKey = "testConfigKey"
        sut = ConfigurationService(defaults: testDefaults, configKey: testKey)
    }

    override func tearDown() {
        cancellables.removeAll()
        sut = nil
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - Save & Load Roundtrip

    func testSaveAndLoadRoundtrip() {
        // Modify config
        sut.update { $0.temperature = 0.7 }
        sut.update { $0.selectedProvider = .openAI }

        // Force persist (normally debounced)
        let encoder = JSONEncoder()
        let data = try! encoder.encode(sut.configuration)
        testDefaults.set(data, forKey: testKey)

        // Create a new instance loading from the same defaults
        let loaded = ConfigurationService(defaults: testDefaults, configKey: testKey)

        XCTAssertEqual(loaded.configuration.temperature, 0.7)
        XCTAssertEqual(loaded.configuration.selectedProvider, .openAI)
    }

    // MARK: - Update Triggers Save

    func testChangingPropertyTriggersUpdate() {
        let expectation = XCTestExpectation(description: "Configuration should update")

        sut.$configuration
            .dropFirst() // Skip initial value
            .sink { config in
                if config.temperature == 0.9 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        sut.update { $0.temperature = 0.9 }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Reset

    func testResetRestoresAllDefaults() {
        sut.update { config in
            config.temperature = 0.99
            config.selectedProvider = .ollama
            config.maxOutputTokens = 8192
            config.autoCopyToClipboard = false
            config.historyLimit = 100
        }

        sut.resetToDefaults()

        XCTAssertEqual(sut.configuration.temperature, AppConfiguration.default.temperature)
        XCTAssertEqual(sut.configuration.selectedProvider, AppConfiguration.default.selectedProvider)
        XCTAssertEqual(sut.configuration.maxOutputTokens, AppConfiguration.default.maxOutputTokens)
        XCTAssertEqual(sut.configuration.autoCopyToClipboard, AppConfiguration.default.autoCopyToClipboard)
        XCTAssertEqual(sut.configuration.historyLimit, AppConfiguration.default.historyLimit)
    }

    // MARK: - Export / Import

    func testExportProducesValidJSON() {
        sut.update { $0.temperature = 0.42 }

        let data = sut.exportAsJSON()
        XCTAssertNotNil(data)

        // Verify it's valid JSON
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        XCTAssertNotNil(json)
    }

    func testImportWithValidJSONRestoresSettings() {
        // Create a config with specific values
        var config = AppConfiguration.default
        config.temperature = 0.85
        config.selectedProvider = .openAI
        config.maxOutputTokens = 4096

        let encoder = JSONEncoder()
        let data = try! encoder.encode(config)

        let result = sut.importFromJSON(data)
        XCTAssertTrue(result)
        XCTAssertEqual(sut.configuration.temperature, 0.85)
        XCTAssertEqual(sut.configuration.selectedProvider, .openAI)
        XCTAssertEqual(sut.configuration.maxOutputTokens, 4096)
    }

    func testImportWithInvalidJSONFailsGracefully() {
        let invalidData = "this is not json".data(using: .utf8)!

        let result = sut.importFromJSON(invalidData)
        XCTAssertFalse(result)

        // Config should be unchanged
        XCTAssertEqual(sut.configuration.temperature, AppConfiguration.default.temperature)
    }

    // MARK: - Default Values

    func testNewServiceStartsWithDefaults() {
        XCTAssertEqual(sut.configuration, AppConfiguration.default)
    }

    func testUpdateMultipleProperties() {
        sut.update { config in
            config.temperature = 0.5
            config.selectedModelName = "gpt-4o-mini"
            config.selectedProvider = .openAI
        }

        XCTAssertEqual(sut.configuration.temperature, 0.5)
        XCTAssertEqual(sut.configuration.selectedModelName, "gpt-4o-mini")
        XCTAssertEqual(sut.configuration.selectedProvider, .openAI)
    }
}

// MARK: - Keychain Service Tests

final class KeychainServiceTests: XCTestCase {

    private var sut: KeychainService!
    private var cleanup: (() -> Void)!

    override func setUp() {
        super.setUp()
        let testInstance = KeychainService.testInstance()
        sut = testInstance.service
        cleanup = testInstance.cleanup
    }

    override func tearDown() {
        cleanup()
        sut = nil
        super.tearDown()
    }

    func testSaveAndLoadAPIKey() {
        let result = sut.saveAPIKey(for: .anthropicClaude, key: "sk-test-key-123")
        switch result {
        case .success: break
        case .failure(let error): XCTFail("Save should succeed: \(error)")
        }

        let loaded = sut.getAPIKey(for: .anthropicClaude)
        XCTAssertEqual(loaded, "sk-test-key-123")
    }

    func testDeleteAPIKey() {
        sut.saveAPIKey(for: .openAI, key: "sk-openai-key")
        XCTAssertNotNil(sut.getAPIKey(for: .openAI))

        let deleted = sut.deleteAPIKey(for: .openAI)
        XCTAssertTrue(deleted)
        XCTAssertNil(sut.getAPIKey(for: .openAI))
    }

    func testHasAPIKey() {
        XCTAssertFalse(sut.hasAPIKey(for: .anthropicClaude))

        sut.saveAPIKey(for: .anthropicClaude, key: "test-key")
        XCTAssertTrue(sut.hasAPIKey(for: .anthropicClaude))
    }

    func testGetNonExistentKeyReturnsNil() {
        XCTAssertNil(sut.getAPIKey(for: .ollama))
    }

    func testSaveOverwritesExistingKey() {
        sut.saveAPIKey(for: .anthropicClaude, key: "old-key")
        sut.saveAPIKey(for: .anthropicClaude, key: "new-key")

        XCTAssertEqual(sut.getAPIKey(for: .anthropicClaude), "new-key")
    }

    func testDeleteNonExistentKeySucceeds() {
        let result = sut.deleteAPIKey(for: .custom)
        XCTAssertTrue(result) // Should succeed (item not found is treated as success)
    }

    func testDifferentProvidersStoredIndependently() {
        sut.saveAPIKey(for: .anthropicClaude, key: "claude-key")
        sut.saveAPIKey(for: .openAI, key: "openai-key")

        XCTAssertEqual(sut.getAPIKey(for: .anthropicClaude), "claude-key")
        XCTAssertEqual(sut.getAPIKey(for: .openAI), "openai-key")

        sut.deleteAPIKey(for: .anthropicClaude)
        XCTAssertNil(sut.getAPIKey(for: .anthropicClaude))
        XCTAssertEqual(sut.getAPIKey(for: .openAI), "openai-key")
    }
}
