import Foundation

final class ClaudeProvider: LLMProviderProtocol {
    let displayName = "Anthropic Claude"
    let iconName = "brain.head.profile"
    let providerType: LLMProvider = .anthropicClaude

    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let anthropicVersion = "2023-06-01"
    private let keychainService: KeychainService
    private let session: URLSession

    /// Maximum characters in a streaming response before truncation.
    private let maxResponseLength = 100_000

    init(keychainService: KeychainService = .shared) {
        self.keychainService = keychainService
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Available Models

    /// Hardcoded fallback used when cloud proxy is unreachable.
    static let fallbackModels: [LLMModelInfo] = [
        LLMModelInfo(id: "claude-opus-4-6-20250916", displayName: "Claude Opus 4.6", contextWindow: 200_000, isDefault: true),
        LLMModelInfo(id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5", contextWindow: 200_000, isDefault: false),
        LLMModelInfo(id: "claude-haiku-4-5-20251001", displayName: "Claude Haiku 4.5", contextWindow: 200_000, isDefault: false),
        LLMModelInfo(id: "claude-3-5-sonnet-20241022", displayName: "Claude 3.5 Sonnet", contextWindow: 200_000, isDefault: false),
        LLMModelInfo(id: "claude-3-5-haiku-20241022", displayName: "Claude 3.5 Haiku", contextWindow: 200_000, isDefault: false),
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
        guard let url = URL(string: AppConstants.CloudAPI.claudeModelsURL) else { return nil }
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
            Logger.shared.warning("Claude: cloud proxy model fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Validate API Key

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "Hi"]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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
        AsyncThrowingStream { continuation in
            let task = Task {
                var totalLength = 0
                do {
                    guard let apiKey = keychainService.getAPIKey(for: .anthropicClaude) else {
                        throw LLMError.noAPIKey
                    }

                    Logger.shared.info("Claude: starting stream for model \(parameters.model)")

                    let request = try buildStreamRequest(messages: messages, parameters: parameters, apiKey: apiKey)
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

                        // Skip malformed chunks gracefully
                        guard let event = try? JSONDecoder().decode(ClaudeSSEEvent.self, from: data) else {
                            Logger.shared.warning("Claude: skipped malformed SSE chunk")
                            continue
                        }

                        // Check for API error events
                        if event.type == "error", let errMsg = event.error?.message {
                            Logger.shared.error("Claude: stream error event: \(errMsg)")
                            throw LLMError.serverError(statusCode: 0, message: errMsg)
                        }

                        if let text = event.textDelta {
                            totalLength += text.count
                            if totalLength > maxResponseLength {
                                Logger.shared.warning("Claude: response exceeded \(maxResponseLength) chars, truncating")
                                continuation.finish(throwing: LLMError.responseTooLong(truncatedOutput: ""))
                                return
                            }
                            continuation.yield(text)
                        }
                    }

                    Logger.shared.info("Claude: stream completed (\(totalLength) chars)")
                    continuation.finish()
                } catch is CancellationError {
                    Logger.shared.info("Claude: stream cancelled")
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as LLMError {
                    Logger.shared.error("Claude: stream error", error: error)
                    continuation.finish(throwing: error)
                } catch let urlError as URLError {
                    Logger.shared.error("Claude: network error", error: urlError)
                    if totalLength > 0 {
                        // Data was already streamed — treat as partial response
                        continuation.finish(throwing: LLMError.partialResponse(partialOutput: ""))
                    } else {
                        continuation.finish(throwing: LLMError.classify(urlError, providerName: "Anthropic Claude"))
                    }
                } catch {
                    Logger.shared.error("Claude: unexpected error", error: error)
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

    // MARK: - Private Helpers

    private func buildStreamRequest(
        messages: [LLMMessage],
        parameters: LLMRequestParameters,
        apiKey: String
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        // Separate system message from conversation messages
        var systemText: String?
        var conversationMessages: [[String: String]] = []

        for msg in messages {
            switch msg.role {
            case .system:
                systemText = msg.content
            case .user:
                conversationMessages.append(["role": "user", "content": msg.content])
            case .assistant:
                conversationMessages.append(["role": "assistant", "content": msg.content])
            }
        }

        var body: [String: Any] = [
            "model": parameters.model,
            "max_tokens": parameters.maxTokens,
            "temperature": parameters.temperature,
            "stream": true,
            "messages": conversationMessages,
        ]

        if let system = systemText {
            body["system"] = system
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
            throw LLMError.serverError(statusCode: response.statusCode, message: "Anthropic server error")
        default:
            throw LLMError.serverError(statusCode: response.statusCode, message: "Unexpected status code")
        }
    }
}

// MARK: - SSE Event Parsing

private struct ClaudeSSEEvent: Decodable {
    let type: String?
    let delta: Delta?
    let error: ClaudeAPIError?

    struct Delta: Decodable {
        let type: String?
        let text: String?
    }

    struct ClaudeAPIError: Decodable {
        let type: String?
        let message: String?
    }

    var textDelta: String? {
        guard type == "content_block_delta", delta?.type == "text_delta" else { return nil }
        return delta?.text
    }
}
