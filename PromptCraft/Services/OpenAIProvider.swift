import Foundation

final class OpenAIProvider: LLMProviderProtocol {
    let displayName = "OpenAI"
    let iconName = "bubble.left.and.text.bubble.right"
    let providerType: LLMProvider = .openAI

    private let chatCompletionsURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let responsesURL = URL(string: "https://api.openai.com/v1/responses")!
    private let keychainService: KeychainService
    private let session: URLSession

    /// Maximum characters in a streaming response before truncation.
    private let maxResponseLength = 100_000

    /// Models that only work with the Responses API (not Chat Completions).
    private static let responsesAPIOnlyModels: Set<String> = [
        "gpt-5.2-pro", "gpt-5-pro", "o3-pro", "o1-pro",
    ]

    /// Check if a model requires the Responses API.
    private func usesResponsesAPI(_ model: String) -> Bool {
        Self.responsesAPIOnlyModels.contains(model) || model.hasSuffix("-pro")
    }

    init(keychainService: KeychainService = .shared) {
        self.keychainService = keychainService
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Available Models

    /// Hardcoded fallback used when cloud proxy is unreachable.
    static let fallbackModels: [LLMModelInfo] = [
        LLMModelInfo(id: "gpt-5.2", displayName: "GPT-5.2", contextWindow: 1_047_576, isDefault: true),
        LLMModelInfo(id: "gpt-5.2-pro", displayName: "GPT-5.2 Pro", contextWindow: 1_047_576, isDefault: false),
        LLMModelInfo(id: "gpt-5.1", displayName: "GPT-5.1", contextWindow: 1_047_576, isDefault: false),
        LLMModelInfo(id: "gpt-5", displayName: "GPT-5", contextWindow: 1_047_576, isDefault: false),
        LLMModelInfo(id: "gpt-5-mini", displayName: "GPT-5 Mini", contextWindow: 1_047_576, isDefault: false),
        LLMModelInfo(id: "gpt-5-nano", displayName: "GPT-5 Nano", contextWindow: 1_047_576, isDefault: false),
        LLMModelInfo(id: "gpt-4.1", displayName: "GPT-4.1", contextWindow: 1_047_576, isDefault: false),
        LLMModelInfo(id: "gpt-4.1-mini", displayName: "GPT-4.1 Mini", contextWindow: 1_047_576, isDefault: false),
        LLMModelInfo(id: "gpt-4.1-nano", displayName: "GPT-4.1 Nano", contextWindow: 1_047_576, isDefault: false),
        LLMModelInfo(id: "gpt-4o", displayName: "GPT-4o", contextWindow: 128_000, isDefault: false),
        LLMModelInfo(id: "gpt-4o-mini", displayName: "GPT-4o Mini", contextWindow: 128_000, isDefault: false),
        LLMModelInfo(id: "o4-mini", displayName: "o4 Mini", contextWindow: 200_000, isDefault: false),
        LLMModelInfo(id: "o3", displayName: "o3", contextWindow: 200_000, isDefault: false),
        LLMModelInfo(id: "o3-pro", displayName: "o3 Pro", contextWindow: 200_000, isDefault: false),
        LLMModelInfo(id: "o3-mini", displayName: "o3 Mini", contextWindow: 200_000, isDefault: false),
    ]

    private static var cachedModels: [LLMModelInfo]?
    private static var lastFetch: Date?

    func availableModels() async throws -> [LLMModelInfo] {
        // Return cache if fresh (1 hour)
        if let cached = Self.cachedModels,
           let lastFetch = Self.lastFetch,
           Date().timeIntervalSince(lastFetch) < 3600 {
            return cached
        }

        // Fetch from cloud proxy
        if let models = await fetchModelsFromProxy() {
            Self.cachedModels = models
            Self.lastFetch = Date()
            return models
        }

        return Self.cachedModels ?? Self.fallbackModels
    }

    private func fetchModelsFromProxy() async -> [LLMModelInfo]? {
        guard let url = URL(string: AppConstants.CloudAPI.openaiModelsURL) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let decoded = try JSONDecoder().decode(CloudModelsResponse.self, from: data)
            let models = decoded.models.enumerated().map { index, m in
                LLMModelInfo(
                    id: m.id,
                    displayName: m.displayName,
                    contextWindow: m.contextWindow,
                    isDefault: index == 0
                )
            }
            return models.isEmpty ? nil : models
        } catch {
            Logger.shared.warning("OpenAI: cloud proxy model fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Validate API Key

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMError.unknown(message: "Invalid response")
            }

            switch httpResponse.statusCode {
            case 200: return true
            case 401: throw LLMError.invalidAPIKey
            default: throw LLMError.serverError(statusCode: httpResponse.statusCode, message: "Validation failed")
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
        if usesResponsesAPI(parameters.model) {
            return streamViaResponsesAPI(messages: messages, parameters: parameters)
        } else {
            return streamViaChatCompletions(messages: messages, parameters: parameters)
        }
    }

    // MARK: - Chat Completions Streaming (standard models)

    private func streamViaChatCompletions(
        messages: [LLMMessage],
        parameters: LLMRequestParameters
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var totalLength = 0
                do {
                    guard let apiKey = keychainService.getAPIKey(for: .openAI) else {
                        throw LLMError.noAPIKey
                    }

                    Logger.shared.info("OpenAI: starting chat completions stream for model \(parameters.model)")

                    let request = try buildChatCompletionsRequest(messages: messages, parameters: parameters, apiKey: apiKey)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMError.unknown(message: "Invalid response")
                    }

                    try handleHTTPStatus(httpResponse)

                    // Parse SSE stream
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]" else { break }
                        guard let data = jsonString.data(using: .utf8) else { continue }

                        guard let event = try? JSONDecoder().decode(ChatCompletionsSSEEvent.self, from: data) else {
                            Logger.shared.warning("OpenAI: skipped malformed SSE chunk")
                            continue
                        }

                        if let text = event.contentDelta {
                            totalLength += text.count
                            if totalLength > maxResponseLength {
                                Logger.shared.warning("OpenAI: response exceeded \(maxResponseLength) chars, truncating")
                                continuation.finish(throwing: LLMError.responseTooLong(truncatedOutput: ""))
                                return
                            }
                            continuation.yield(text)
                        }
                    }

                    Logger.shared.info("OpenAI: stream completed (\(totalLength) chars)")
                    continuation.finish()
                } catch is CancellationError {
                    Logger.shared.info("OpenAI: stream cancelled")
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as LLMError {
                    Logger.shared.error("OpenAI: stream error", error: error)
                    continuation.finish(throwing: error)
                } catch let urlError as URLError {
                    Logger.shared.error("OpenAI: network error", error: urlError)
                    if totalLength > 0 {
                        continuation.finish(throwing: LLMError.partialResponse(partialOutput: ""))
                    } else {
                        continuation.finish(throwing: LLMError.classify(urlError, providerName: "OpenAI"))
                    }
                } catch {
                    Logger.shared.error("OpenAI: unexpected error", error: error)
                    if totalLength > 0 {
                        continuation.finish(throwing: LLMError.partialResponse(partialOutput: ""))
                    } else {
                        continuation.finish(throwing: LLMError.networkError(underlying: error))
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Responses API Streaming (pro models)

    private func streamViaResponsesAPI(
        messages: [LLMMessage],
        parameters: LLMRequestParameters
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var totalLength = 0
                do {
                    guard let apiKey = keychainService.getAPIKey(for: .openAI) else {
                        throw LLMError.noAPIKey
                    }

                    Logger.shared.info("OpenAI: starting Responses API stream for model \(parameters.model)")

                    let request = try buildResponsesRequest(messages: messages, parameters: parameters, apiKey: apiKey)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMError.unknown(message: "Invalid response")
                    }

                    try handleHTTPStatus(httpResponse)

                    // Parse Responses API SSE stream
                    // Format: "event: <type>\ndata: <json>\n\n"
                    var currentEventType: String?

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        if line.hasPrefix("event: ") {
                            currentEventType = String(line.dropFirst(7))
                            continue
                        }

                        guard line.hasPrefix("data: "),
                              let eventType = currentEventType else { continue }

                        let jsonString = String(line.dropFirst(6))
                        guard let data = jsonString.data(using: .utf8) else { continue }

                        switch eventType {
                        case "response.output_text.delta":
                            if let delta = try? JSONDecoder().decode(ResponsesTextDelta.self, from: data) {
                                totalLength += delta.delta.count
                                if totalLength > maxResponseLength {
                                    Logger.shared.warning("OpenAI: Responses API exceeded \(maxResponseLength) chars, truncating")
                                    continuation.finish(throwing: LLMError.responseTooLong(truncatedOutput: ""))
                                    return
                                }
                                continuation.yield(delta.delta)
                            }

                        case "response.completed":
                            Logger.shared.info("OpenAI: Responses API stream completed (\(totalLength) chars)")

                        case "response.failed":
                            if let failure = try? JSONDecoder().decode(ResponsesFailedEvent.self, from: data),
                               let errorMsg = failure.response?.error?.message {
                                throw LLMError.serverError(statusCode: 0, message: errorMsg)
                            }
                            throw LLMError.unknown(message: "OpenAI Responses API returned an error")

                        default:
                            break
                        }

                        currentEventType = nil
                    }

                    continuation.finish()
                } catch is CancellationError {
                    Logger.shared.info("OpenAI: Responses API stream cancelled")
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as LLMError {
                    Logger.shared.error("OpenAI: Responses API error", error: error)
                    continuation.finish(throwing: error)
                } catch let urlError as URLError {
                    Logger.shared.error("OpenAI: Responses API network error", error: urlError)
                    if totalLength > 0 {
                        continuation.finish(throwing: LLMError.partialResponse(partialOutput: ""))
                    } else {
                        continuation.finish(throwing: LLMError.classify(urlError, providerName: "OpenAI"))
                    }
                } catch {
                    Logger.shared.error("OpenAI: Responses API unexpected error", error: error)
                    if totalLength > 0 {
                        continuation.finish(throwing: LLMError.partialResponse(partialOutput: ""))
                    } else {
                        continuation.finish(throwing: LLMError.networkError(underlying: error))
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Request Builders

    private func buildChatCompletionsRequest(
        messages: [LLMMessage],
        parameters: LLMRequestParameters,
        apiKey: String
    ) throws -> URLRequest {
        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var chatMessages: [[String: String]] = []
        for msg in messages {
            chatMessages.append(["role": msg.role.rawValue, "content": msg.content])
        }

        // Reasoning models (o1, o3, o4) don't support temperature or system messages
        let isReasoningModel = parameters.model.hasPrefix("o1") || parameters.model.hasPrefix("o3") || parameters.model.hasPrefix("o4")

        var body: [String: Any] = [
            "model": parameters.model,
            "stream": true,
            "messages": chatMessages,
        ]

        if isReasoningModel {
            body["max_completion_tokens"] = parameters.maxTokens
        } else {
            body["max_tokens"] = parameters.maxTokens
            body["temperature"] = parameters.temperature
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildResponsesRequest(
        messages: [LLMMessage],
        parameters: LLMRequestParameters,
        apiKey: String
    ) throws -> URLRequest {
        var request = URLRequest(url: responsesURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        // Responses API uses "input" array with typed messages
        // System messages go into "instructions" parameter
        var inputMessages: [[String: String]] = []
        var instructions: String?

        for msg in messages {
            if msg.role == .system {
                instructions = msg.content
            } else {
                inputMessages.append([
                    "type": "message",
                    "role": msg.role.rawValue,
                    "content": msg.content,
                ])
            }
        }

        var body: [String: Any] = [
            "model": parameters.model,
            "stream": true,
            "input": inputMessages,
        ]

        if let instructions {
            body["instructions"] = instructions
        }

        if parameters.maxTokens > 0 {
            body["max_output_tokens"] = parameters.maxTokens
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func handleHTTPStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200: return
        case 401: throw LLMError.invalidAPIKey
        case 403: throw LLMError.forbidden
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "retry-after")
                .flatMap { Double($0) } ?? 30.0
            throw LLMError.rateLimited(retryAfter: retryAfter)
        case 400:
            throw LLMError.contextLengthExceeded
        case 503:
            throw LLMError.serviceUnavailable
        case 500...599:
            throw LLMError.serverError(statusCode: response.statusCode, message: "OpenAI server error")
        default:
            throw LLMError.serverError(statusCode: response.statusCode, message: "Unexpected status code")
        }
    }
}

// MARK: - Chat Completions SSE Event Parsing

private struct ChatCompletionsSSEEvent: Decodable {
    let choices: [Choice]?

    struct Choice: Decodable {
        let delta: Delta?
    }

    struct Delta: Decodable {
        let content: String?
    }

    var contentDelta: String? {
        choices?.first?.delta?.content
    }
}

// MARK: - Responses API SSE Event Parsing

private struct ResponsesTextDelta: Decodable {
    let delta: String
}

private struct ResponsesFailedEvent: Decodable {
    let response: ResponseBody?

    struct ResponseBody: Decodable {
        let error: ResponseError?
    }

    struct ResponseError: Decodable {
        let message: String?
    }
}
