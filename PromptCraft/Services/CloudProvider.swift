import Foundation

// MARK: - CloudProvider
//
// LLM provider that routes requests through PromptCraft Cloud.
// Requires a Cloud license. Auth is via license key as Bearer token.
// Streaming uses SSE format matching the Claude provider pattern.

final class CloudProvider: LLMProviderProtocol {
    let displayName = "PromptCraft Cloud"
    let iconName = "cloud.fill"
    let providerType: LLMProvider = .promptCraftCloud

    private let baseURL: URL
    private let session: URLSession
    private let maxResponseLength = 100_000

    init() {
        self.baseURL = URL(string: AppConstants.CloudAPI.baseURL)!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Available Models

    static let supportedModels: [LLMModelInfo] = [
        LLMModelInfo(id: "pc-standard", displayName: "PromptCraft Standard", contextWindow: 128_000, isDefault: true),
        LLMModelInfo(id: "pc-fast", displayName: "PromptCraft Fast", contextWindow: 64_000, isDefault: false),
    ]

    func availableModels() async throws -> [LLMModelInfo] {
        CloudProvider.supportedModels
    }

    // MARK: - Validate API Key (License Key)

    func validateAPIKey(_ key: String) async throws -> Bool {
        // For Cloud, we validate the license key
        let licenseKey = key.isEmpty
            ? LicensingService.shared.licenseKey ?? ""
            : key

        guard !licenseKey.isEmpty else {
            throw LLMError.noAPIKey
        }

        // TODO: Replace with actual cloud endpoint validation
        // var request = URLRequest(url: URL(string: AppConstants.CloudAPI.baseURL)!)
        // request.httpMethod = "POST"
        // request.setValue("Bearer \(licenseKey)", forHTTPHeaderField: "Authorization")
        // ... validate

        // Placeholder: accept if licensing service says we're valid
        return LicensingService.shared.isProUser && LicensingService.shared.licenseType == .cloud
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
                    guard let licenseKey = LicensingService.shared.licenseKey else {
                        throw LLMError.noAPIKey
                    }

                    Logger.shared.info("Cloud: starting stream for model \(parameters.model)")

                    let request = try buildStreamRequest(
                        messages: messages,
                        parameters: parameters,
                        licenseKey: licenseKey
                    )
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMError.unknown(message: "Invalid response")
                    }

                    try handleHTTPStatus(httpResponse)

                    // Parse SSE stream (same format as Claude provider)
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]" else { break }
                        guard let data = jsonString.data(using: .utf8) else { continue }

                        guard let event = try? JSONDecoder().decode(CloudSSEEvent.self, from: data) else {
                            Logger.shared.warning("Cloud: skipped malformed SSE chunk")
                            continue
                        }

                        if event.type == "error", let errMsg = event.error?.message {
                            Logger.shared.error("Cloud: stream error event: \(errMsg)")
                            throw LLMError.serverError(statusCode: 0, message: errMsg)
                        }

                        if let text = event.textDelta {
                            totalLength += text.count
                            if totalLength > maxResponseLength {
                                Logger.shared.warning("Cloud: response exceeded \(maxResponseLength) chars, truncating")
                                continuation.finish(throwing: LLMError.responseTooLong(truncatedOutput: ""))
                                return
                            }
                            continuation.yield(text)
                        }
                    }

                    Logger.shared.info("Cloud: stream completed (\(totalLength) chars)")
                    continuation.finish()
                } catch is CancellationError {
                    Logger.shared.info("Cloud: stream cancelled")
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as LLMError {
                    Logger.shared.error("Cloud: stream error", error: error)
                    continuation.finish(throwing: error)
                } catch let urlError as URLError {
                    Logger.shared.error("Cloud: network error", error: urlError)
                    if totalLength > 0 {
                        continuation.finish(throwing: LLMError.partialResponse(partialOutput: ""))
                    } else {
                        continuation.finish(throwing: LLMError.classify(urlError, providerName: "PromptCraft Cloud"))
                    }
                } catch {
                    Logger.shared.error("Cloud: unexpected error", error: error)
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
        licenseKey: String
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(licenseKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        request.setValue(appVersion, forHTTPHeaderField: "X-PromptCraft-Version")

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
            "license_key": licenseKey,
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
        case 503: throw LLMError.serviceUnavailable
        case 500...599:
            throw LLMError.serverError(statusCode: response.statusCode, message: "PromptCraft Cloud server error")
        default:
            throw LLMError.serverError(statusCode: response.statusCode, message: "Unexpected status code")
        }
    }
}

// MARK: - SSE Event Parsing

private struct CloudSSEEvent: Decodable {
    let type: String?
    let delta: Delta?
    let error: CloudAPIError?

    struct Delta: Decodable {
        let type: String?
        let text: String?
    }

    struct CloudAPIError: Decodable {
        let type: String?
        let message: String?
    }

    var textDelta: String? {
        guard type == "content_block_delta", delta?.type == "text_delta" else { return nil }
        return delta?.text
    }
}
