import Foundation
import XCTest
@testable import PromptCraft

// MARK: - Sample Data Generators

enum TestData {

    static func sampleStyle(
        id: UUID = UUID(),
        displayName: String = "Test Style",
        shortDescription: String = "A test style for unit tests.",
        category: StyleCategory = .technical,
        iconName: String = "hammer",
        sortOrder: Int = 0,
        isBuiltIn: Bool = false,
        isEnabled: Bool = true,
        systemInstruction: String = "You are a helpful assistant. Rewrite the prompt clearly.",
        outputStructure: [String] = ["Context", "Task"],
        toneDescriptor: String = "clear and direct",
        fewShotExamples: [FewShotExample] = [
            FewShotExample(input: "make it better", output: "Please improve the quality of the following text."),
        ],
        enforcedPrefix: String? = nil,
        enforcedSuffix: String? = nil,
        targetModelHint: TargetModelHint = .any
    ) -> PromptStyle {
        PromptStyle(
            id: id,
            displayName: displayName,
            shortDescription: shortDescription,
            category: category,
            iconName: iconName,
            sortOrder: sortOrder,
            isBuiltIn: isBuiltIn,
            isEnabled: isEnabled,
            systemInstruction: systemInstruction,
            outputStructure: outputStructure,
            toneDescriptor: toneDescriptor,
            fewShotExamples: fewShotExamples,
            enforcedPrefix: enforcedPrefix,
            enforcedSuffix: enforcedSuffix,
            targetModelHint: targetModelHint
        )
    }

    static func sampleHistoryEntry(
        id: UUID = UUID(),
        inputText: String = "help me write python code",
        outputText: String = "Write a Python script that...",
        styleID: UUID = DefaultStyles.defaultStyleID,
        timestamp: Date = Date(),
        providerName: String = "Anthropic Claude",
        modelName: String = "claude-sonnet-4-5-20250929",
        durationMilliseconds: Int = 1500,
        isFavorited: Bool = false
    ) -> PromptHistoryEntry {
        PromptHistoryEntry(
            id: id,
            inputText: inputText,
            outputText: outputText,
            styleID: styleID,
            timestamp: timestamp,
            providerName: providerName,
            modelName: modelName,
            durationMilliseconds: durationMilliseconds,
            isFavorited: isFavorited
        )
    }

    static func sampleConfiguration() -> AppConfiguration {
        .default
    }
}

// MARK: - Temporary Directory Helper

class TempDirectoryTestCase: XCTestCase {
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        let tempBase = FileManager.default.temporaryDirectory
        tempDirectory = tempBase.appendingPathComponent("PromptCraftTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }
}

// MARK: - Mock LLM Provider

final class MockLLMProvider: LLMProviderProtocol {
    var displayName: String = "Mock Provider"
    var iconName: String = "cpu"
    var providerType: LLMProvider = .anthropicClaude

    var streamResponse: [String] = ["This is ", "a mocked ", "response."]
    var streamError: Error?
    var validateResult: Bool = true
    var validateError: Error?
    var models: [LLMModelInfo] = [
        LLMModelInfo(id: "mock-model", displayName: "Mock Model", contextWindow: 100_000, isDefault: true),
    ]
    var lastMessages: [LLMMessage]?
    var lastParameters: LLMRequestParameters?

    func streamCompletion(
        messages: [LLMMessage],
        parameters: LLMRequestParameters
    ) -> AsyncThrowingStream<String, Error> {
        lastMessages = messages
        lastParameters = parameters

        return AsyncThrowingStream { continuation in
            if let error = self.streamError {
                continuation.finish(throwing: error)
            } else {
                for chunk in self.streamResponse {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        if let error = validateError { throw error }
        return validateResult
    }

    func availableModels() async throws -> [LLMModelInfo] {
        models
    }
}

// MARK: - Mock Clipboard (for reference in tests that need clipboard verification)
// Note: ClipboardService is final, so we use the real instance in tests.
// The MainViewModel uses the real ClipboardService which accesses NSPasteboard.

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol {
    typealias RequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data)

    static var requestHandler: RequestHandler?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Test UserDefaults

extension UserDefaults {
    static func testSuite(name: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

// MARK: - Test Keychain Service

extension KeychainService {
    /// Creates a KeychainService with a unique test service name.
    /// Call `cleanupTestKeychain()` in tearDown to remove test entries.
    static func testInstance() -> (service: KeychainService, cleanup: () -> Void) {
        let testServiceName = "com.promptcraft.test.\(UUID().uuidString)"
        let service = KeychainService(serviceName: testServiceName)
        let cleanup = {
            for provider in LLMProvider.allCases {
                service.deleteAPIKey(for: provider)
            }
        }
        return (service, cleanup)
    }
}
