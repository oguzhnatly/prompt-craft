import XCTest
@testable import PromptCraft

// MARK: - MockURLProtocol for Streaming

/// A more sophisticated mock that supports streaming responses via URLSession.bytes
final class StreamingMockURLProtocol: URLProtocol {
    typealias RequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data)

    static var requestHandler: RequestHandler?
    static var capturedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        StreamingMockURLProtocol.capturedRequests.append(request)

        guard let handler = StreamingMockURLProtocol.requestHandler else {
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

    static func reset() {
        requestHandler = nil
        capturedRequests = []
    }
}

// MARK: - Provider Integration Tests

final class ClaudeProviderTests: XCTestCase {

    private var keychainService: KeychainService!
    private var keychainCleanup: (() -> Void)!

    override func setUp() {
        super.setUp()
        let result = KeychainService.testInstance()
        keychainService = result.service
        keychainCleanup = result.cleanup
        StreamingMockURLProtocol.reset()
    }

    override func tearDown() {
        keychainCleanup()
        StreamingMockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Supported Models

    func testSupportedModelsIncludeExpectedModels() async throws {
        let provider = ClaudeProvider(keychainService: keychainService)
        let models = try await provider.availableModels()

        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.contains(where: { $0.id.contains("claude") }))
    }

    func testDefaultModelIsSet() async throws {
        let provider = ClaudeProvider(keychainService: keychainService)
        let models = try await provider.availableModels()

        let defaultModel = models.first(where: \.isDefault)
        XCTAssertNotNil(defaultModel)
    }

    // MARK: - Provider Properties

    func testProviderTypeIsClaude() {
        let provider = ClaudeProvider(keychainService: keychainService)
        XCTAssertEqual(provider.providerType, .anthropicClaude)
        XCTAssertEqual(provider.displayName, "Anthropic Claude")
    }
}

final class OpenAIProviderTests: XCTestCase {

    private var keychainService: KeychainService!
    private var keychainCleanup: (() -> Void)!

    override func setUp() {
        super.setUp()
        let result = KeychainService.testInstance()
        keychainService = result.service
        keychainCleanup = result.cleanup
        StreamingMockURLProtocol.reset()
    }

    override func tearDown() {
        keychainCleanup()
        StreamingMockURLProtocol.reset()
        super.tearDown()
    }

    func testSupportedModelsIncludeGPT4o() async throws {
        let provider = OpenAIProvider(keychainService: keychainService)
        let models = try await provider.availableModels()

        XCTAssertTrue(models.contains(where: { $0.id == "gpt-4o" }))
    }

    func testProviderTypeIsOpenAI() {
        let provider = OpenAIProvider(keychainService: keychainService)
        XCTAssertEqual(provider.providerType, .openAI)
        XCTAssertEqual(provider.displayName, "OpenAI")
    }

    func testDefaultModelIsSet() async throws {
        let provider = OpenAIProvider(keychainService: keychainService)
        let models = try await provider.availableModels()

        let defaultModel = models.first(where: \.isDefault)
        XCTAssertNotNil(defaultModel)
        XCTAssertEqual(defaultModel?.id, "gpt-4o")
    }
}

final class OllamaProviderTests: XCTestCase {

    func testProviderTypeIsOllama() {
        let provider = OllamaProvider()
        XCTAssertEqual(provider.providerType, .ollama)
        XCTAssertTrue(provider.displayName.contains("Ollama"))
    }
}

// MARK: - LLM Error Tests

final class LLMErrorTests: XCTestCase {

    func testInvalidAPIKeyErrorDescription() {
        let error = LLMError.invalidAPIKey
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.isAPIKeyError)
    }

    func testNoAPIKeyErrorDescription() {
        let error = LLMError.noAPIKey
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.isAPIKeyError)
    }

    func testRateLimitedErrorDescription() {
        let error = LLMError.rateLimited(retryAfter: 30)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("30"))
        XCTAssertFalse(error.isAPIKeyError)
    }

    func testPartialResponseHasPartialOutput() {
        let error = LLMError.partialResponse(partialOutput: "partial text")
        XCTAssertEqual(error.partialOutput, "partial text")
    }

    func testResponseTooLongHasPartialOutput() {
        let error = LLMError.responseTooLong(truncatedOutput: "truncated")
        XCTAssertEqual(error.partialOutput, "truncated")
    }

    func testNetworkErrorClassification() {
        let urlError = URLError(.timedOut)
        let classified = LLMError.classify(urlError, providerName: "Test")
        if case .timeout = classified {
            // correct
        } else {
            XCTFail("Timeout should be classified as .timeout")
        }
    }

    func testDNSFailureClassification() {
        let urlError = URLError(.dnsLookupFailed)
        let classified = LLMError.classify(urlError, providerName: "TestProvider")
        if case .dnsFailure(let name) = classified {
            XCTAssertEqual(name, "TestProvider")
        } else {
            XCTFail("DNS failure should be classified as .dnsFailure")
        }
    }

    func testSSLErrorClassification() {
        let urlError = URLError(.secureConnectionFailed)
        let classified = LLMError.classify(urlError, providerName: "Test")
        if case .sslError = classified {
            // correct
        } else {
            XCTFail("SSL error should be classified as .sslError")
        }
    }

    func testNoInternetClassification() {
        let urlError = URLError(.notConnectedToInternet)
        let classified = LLMError.classify(urlError, providerName: "Test")
        if case .noNetwork = classified {
            // correct
        } else {
            XCTFail("Not connected should be classified as .noNetwork")
        }
    }

    func testCannotConnectClassification() {
        let urlError = URLError(.cannotConnectToHost)
        let classified = LLMError.classify(urlError, providerName: "Test")
        if case .networkError = classified {
            // correct
        } else {
            XCTFail("Cannot connect should be classified as .networkError")
        }
    }

    func testCancelledError() {
        let error = LLMError.cancelled
        XCTAssertEqual(error.errorDescription, "Request cancelled.")
        XCTAssertFalse(error.isAPIKeyError)
        XCTAssertNil(error.partialOutput)
    }

    func testServerError() {
        let error = LLMError.serverError(statusCode: 500, message: "Internal error")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("500"))
        XCTAssertTrue(error.errorDescription!.contains("Internal error"))
    }

    func testAllErrorCasesHaveDescriptions() {
        let errors: [LLMError] = [
            .invalidAPIKey,
            .forbidden,
            .rateLimited(retryAfter: 10),
            .networkError(underlying: URLError(.badURL)),
            .timeout,
            .dnsFailure(providerName: "Test"),
            .sslError,
            .modelUnavailable,
            .contextLengthExceeded,
            .serverError(statusCode: 500, message: "test"),
            .serviceUnavailable,
            .partialResponse(partialOutput: ""),
            .responseTooLong(truncatedOutput: ""),
            .unknown(message: "test"),
            .noAPIKey,
            .noNetwork,
            .cancelled,
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
        }
    }
}

// MARK: - LLM Provider Manager Tests

final class LLMProviderManagerTests: XCTestCase {

    private var configService: ConfigurationService!
    private var keychainService: KeychainService!
    private var keychainCleanup: (() -> Void)!

    override func setUp() {
        super.setUp()
        let suiteName = "com.promptcraft.pmtest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        configService = ConfigurationService(defaults: defaults, configKey: "testPMConfig")

        let result = KeychainService.testInstance()
        keychainService = result.service
        keychainCleanup = result.cleanup
    }

    override func tearDown() {
        keychainCleanup()
        super.tearDown()
    }

    func testActiveProviderMatchesConfiguration() {
        let manager = LLMProviderManager(
            configurationService: configService,
            keychainService: keychainService
        )

        configService.update { $0.selectedProvider = .anthropicClaude }
        XCTAssertEqual(manager.activeProvider.providerType, .anthropicClaude)

        configService.update { $0.selectedProvider = .openAI }
        XCTAssertEqual(manager.activeProvider.providerType, .openAI)

        configService.update { $0.selectedProvider = .ollama }
        XCTAssertEqual(manager.activeProvider.providerType, .ollama)
    }

    func testSwitchProviderUpdatesConfiguration() {
        let manager = LLMProviderManager(
            configurationService: configService,
            keychainService: keychainService
        )

        manager.switchProvider(to: .openAI)
        XCTAssertEqual(configService.configuration.selectedProvider, .openAI)
    }

    func testAllProviderStatuses() {
        let manager = LLMProviderManager(
            configurationService: configService,
            keychainService: keychainService
        )

        let statuses = manager.allProviderStatuses()
        XCTAssertGreaterThanOrEqual(statuses.count, 3) // Claude, OpenAI, Ollama

        // Ollama should always show hasAPIKey = true
        let ollamaStatus = statuses.first(where: { $0.provider == .ollama })
        XCTAssertNotNil(ollamaStatus)
        XCTAssertTrue(ollamaStatus!.hasAPIKey)
    }

    func testProviderForType() {
        let manager = LLMProviderManager(
            configurationService: configService,
            keychainService: keychainService
        )

        XCTAssertEqual(manager.provider(for: .anthropicClaude).providerType, .anthropicClaude)
        XCTAssertEqual(manager.provider(for: .openAI).providerType, .openAI)
        XCTAssertEqual(manager.provider(for: .ollama).providerType, .ollama)
    }
}
