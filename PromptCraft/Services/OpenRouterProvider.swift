import Foundation

// MARK: - OpenRouter Provider
// Uses the OpenAI-compatible API at https://openrouter.ai/api/v1
// Gives access to: DeepSeek, Llama 3, Mistral, Grok (xAI), MiniMax, Kimi, GLM, Arcee, Gemini, and 200+ more

final class OpenRouterProvider: LLMProviderProtocol {
    let displayName = "OpenRouter"
    let iconName = "network"
    let providerType: LLMProvider = .openRouter

    private let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let modelsURL = URL(string: "https://openrouter.ai/api/v1/models")!
    private let keychainService: KeychainService
    private let session: URLSession

    private static var cachedModels: [LLMModelInfo]?
    private static var lastFetch: Date?

    init(keychainService: KeychainService = .shared) {
        self.keychainService = keychainService
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Curated Top Models

    /// Curated top models from OpenRouter rankings covering all major providers.
    static let curatedModels: [LLMModelInfo] = [
        // DeepSeek
        LLMModelInfo(id: "deepseek/deepseek-chat-v3-0324", displayName: "DeepSeek V3", contextWindow: 163_840, isDefault: true),
        LLMModelInfo(id: "deepseek/deepseek-r1", displayName: "DeepSeek R1", contextWindow: 163_840, isDefault: false),

        // Meta Llama
        LLMModelInfo(id: "meta-llama/llama-4-maverick", displayName: "Llama 4 Maverick", contextWindow: 1_048_576, isDefault: false),
        LLMModelInfo(id: "meta-llama/llama-4-scout", displayName: "Llama 4 Scout", contextWindow: 512_000, isDefault: false),
        LLMModelInfo(id: "meta-llama/llama-3.3-70b-instruct", displayName: "Llama 3.3 70B", contextWindow: 131_072, isDefault: false),

        // Google Gemini (via OpenRouter)
        LLMModelInfo(id: "google/gemini-2.5-pro-preview", displayName: "Gemini 2.5 Pro", contextWindow: 1_048_576, isDefault: false),
        LLMModelInfo(id: "google/gemini-2.0-flash-001", displayName: "Gemini 2.0 Flash", contextWindow: 1_048_576, isDefault: false),

        // Mistral
        LLMModelInfo(id: "mistralai/mistral-large-2411", displayName: "Mistral Large", contextWindow: 131_072, isDefault: false),
        LLMModelInfo(id: "mistralai/mistral-small-3.1-24b-instruct", displayName: "Mistral Small 3.1", contextWindow: 128_000, isDefault: false),
        LLMModelInfo(id: "mistralai/codestral-2501", displayName: "Codestral", contextWindow: 262_144, isDefault: false),

        // xAI Grok
        LLMModelInfo(id: "x-ai/grok-3-beta", displayName: "Grok 3 Beta", contextWindow: 131_072, isDefault: false),
        LLMModelInfo(id: "x-ai/grok-3-mini-beta", displayName: "Grok 3 Mini", contextWindow: 131_072, isDefault: false),

        // MiniMax
        LLMModelInfo(id: "minimax/minimax-m1", displayName: "MiniMax M1", contextWindow: 1_000_000, isDefault: false),

        // Moonshot Kimi
        LLMModelInfo(id: "moonshotai/kimi-k2", displayName: "Kimi K2", contextWindow: 131_072, isDefault: false),

        // Zhipu GLM
        LLMModelInfo(id: "thudm/glm-4-32b", displayName: "GLM-4 32B", contextWindow: 131_072, isDefault: false),

        // Arcee
        LLMModelInfo(id: "arcee-ai/arcee-prism", displayName: "Arcee Prism", contextWindow: 131_072, isDefault: false),

        // Qwen (Alibaba)
        LLMModelInfo(id: "qwen/qwen3-235b-a22b", displayName: "Qwen 3 235B", contextWindow: 32_768, isDefault: false),
        LLMModelInfo(id: "qwen/qwen3-32b", displayName: "Qwen 3 32B", contextWindow: 32_768, isDefault: false),

        // Cohere
        LLMModelInfo(id: "cohere/command-r-plus-08-2024", displayName: "Command R+", contextWindow: 128_000, isDefault: false),

        // Nous Research
        LLMModelInfo(id: "nousresearch/hermes-3-llama-3.1-405b", displayName: "Hermes 3 405B", contextWindow: 131_072, isDefault: false),
    ]

    // MARK: - Available Models

    func availableModels() async throws -> [LLMModelInfo] {
        // Return cache if fresh (30 minutes)
        if let cached = Self.cachedModels,
           let lastFetch = Self.lastFetch,
           Date().timeIntervalSince(lastFetch) < 1800 {
            return cached
        }

        // Fetch live model list from OpenRouter
        if let live = await fetchModelsFromAPI() {
            Self.cachedModels = live
            Self.lastFetch = Date()
            return live
        }

        return Self.curatedModels
    }

    private func fetchModelsFromAPI() async -> [LLMModelInfo]? {
        // 1. Try cloud proxy first (cached, no auth required)
        if let proxyModels = await fetchModelsFromProxy() {
            return proxyModels
        }

        // 2. Fall back to direct OpenRouter API (requires key)
        guard let apiKey = keychainService.getAPIKey(for: .openRouter) else {
            return nil
        }

        var request = URLRequest(url: modelsURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
            let models = decoded.data
                .filter { $0.supportsCompletions }
                .prefix(80)
                .enumerated()
                .map { index, m -> LLMModelInfo in
                    LLMModelInfo(
                        id: m.id,
                        displayName: m.name,
                        contextWindow: m.contextLength ?? 8192,
                        isDefault: index == 0
                    )
                }
            return models.isEmpty ? nil : Array(models)
        } catch {
            Logger.shared.warning("OpenRouter: direct API model fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchModelsFromProxy() async -> [LLMModelInfo]? {
        guard let url = URL(string: AppConstants.CloudAPI.openRouterModelsURL) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let decoded = try JSONDecoder().decode(OpenRouterProxyResponse.self, from: data)
            let models = decoded.models
                .enumerated()
                .map { index, m -> LLMModelInfo in
                    LLMModelInfo(
                        id: m.id,
                        displayName: m.displayName,
                        contextWindow: m.contextLength,
                        isDefault: index == 0
                    )
                }
            return models.isEmpty ? nil : models
        } catch {
            Logger.shared.warning("OpenRouter: proxy model fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Validate API Key

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/key")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMError.unknown(message: "Invalid response")
            }

            switch httpResponse.statusCode {
            case 200: return true
            case 401: throw LLMError.invalidAPIKey
            default:
                throw LLMError.serverError(statusCode: httpResponse.statusCode, message: "Validation failed")
            }
        } catch let error as LLMError {
            throw error
        } catch let urlError as URLError {
            throw LLMError.classify(urlError, providerName: displayName)
        } catch {
            throw LLMError.networkError(underlying: error)
        }
    }

    // MARK: - Streaming

    func streamCompletion(
        messages: [LLMMessage],
        parameters: LLMRequestParameters
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var totalLength = 0
                do {
                    guard let apiKey = keychainService.getAPIKey(for: .openRouter) else {
                        throw LLMError.noAPIKey
                    }

                    Logger.shared.info("OpenRouter: starting stream for model \(parameters.model)")

                    let request = try buildRequest(
                        messages: messages,
                        parameters: parameters,
                        apiKey: apiKey
                    )
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMError.unknown(message: "Invalid response")
                    }

                    try handleHTTPStatus(httpResponse)

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]" else { break }
                        guard let data = jsonString.data(using: .utf8) else { continue }

                        guard let event = try? JSONDecoder().decode(OpenRouterSSEEvent.self, from: data) else {
                            continue
                        }

                        // OpenRouter may send error events inline
                        if let errorMsg = event.error?.message {
                            throw LLMError.serverError(statusCode: event.error?.code ?? 0, message: errorMsg)
                        }

                        if let text = event.contentDelta {
                            totalLength += text.count
                            if totalLength > 100_000 {
                                continuation.finish(throwing: LLMError.responseTooLong(truncatedOutput: ""))
                                return
                            }
                            continuation.yield(text)
                        }
                    }

                    Logger.shared.info("OpenRouter: stream completed (\(totalLength) chars)")
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as LLMError {
                    Logger.shared.error("OpenRouter: stream error", error: error)
                    continuation.finish(throwing: error)
                } catch let urlError as URLError {
                    if totalLength > 0 {
                        continuation.finish(throwing: LLMError.partialResponse(partialOutput: ""))
                    } else {
                        continuation.finish(throwing: LLMError.classify(urlError, providerName: displayName))
                    }
                } catch {
                    if totalLength > 0 {
                        continuation.finish(throwing: LLMError.partialResponse(partialOutput: ""))
                    } else {
                        continuation.finish(throwing: LLMError.networkError(underlying: error))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request Builder

    private func buildRequest(
        messages: [LLMMessage],
        parameters: LLMRequestParameters,
        apiKey: String
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://promptcraft.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("PromptCraft", forHTTPHeaderField: "X-Title")

        let chatMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": parameters.model,
            "messages": chatMessages,
            "stream": true,
            "max_tokens": parameters.maxTokens,
            "temperature": parameters.temperature,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func handleHTTPStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200: return
        case 401: throw LLMError.invalidAPIKey
        case 402: throw LLMError.forbidden
        case 403: throw LLMError.forbidden
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "retry-after")
                .flatMap { Double($0) } ?? 30.0
            throw LLMError.rateLimited(retryAfter: retryAfter)
        case 503: throw LLMError.serviceUnavailable
        case 500...599: throw LLMError.serverError(statusCode: response.statusCode, message: "OpenRouter server error")
        default: throw LLMError.serverError(statusCode: response.statusCode, message: "Unexpected status")
        }
    }
}

// MARK: - Response Types

private struct OpenRouterSSEEvent: Decodable {
    let choices: [Choice]?
    let error: OpenRouterError?

    struct Choice: Decodable {
        let delta: Delta?
    }

    struct Delta: Decodable {
        let content: String?
    }

    struct OpenRouterError: Decodable {
        let message: String?
        let code: Int?
    }

    var contentDelta: String? {
        choices?.first?.delta?.content
    }
}

private struct OpenRouterProxyResponse: Decodable {
    let models: [ProxyModel]

    struct ProxyModel: Decodable {
        let id: String
        let displayName: String
        let contextLength: Int
        let provider: String
    }
}

private struct OpenRouterModelsResponse: Decodable {
    let data: [ModelEntry]

    struct ModelEntry: Decodable {
        let id: String
        let name: String
        let contextLength: Int?

        /// Only include models that support chat completions (not image/audio only).
        var supportsCompletions: Bool {
            !id.contains("dall-e") && !id.contains("whisper") && !id.contains("tts")
        }

        enum CodingKeys: String, CodingKey {
            case id, name
            case contextLength = "context_length"
        }
    }
}
