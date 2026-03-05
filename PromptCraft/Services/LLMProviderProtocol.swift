import Foundation

// MARK: - LLM Errors

enum LLMError: LocalizedError {
    case invalidAPIKey
    case forbidden
    case rateLimited(retryAfter: TimeInterval)
    case networkError(underlying: Error)
    case timeout
    case dnsFailure(providerName: String)
    case sslError
    case modelUnavailable
    case contextLengthExceeded
    case serverError(statusCode: Int, message: String)
    case serviceUnavailable
    case partialResponse(partialOutput: String)
    case responseTooLong(truncatedOutput: String)
    case unknown(message: String)
    case noAPIKey
    case noNetwork
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key. Update your key in Settings."
        case .forbidden:
            return "Access denied. Your API key may not have permission for this model."
        case .rateLimited(let retryAfter):
            let seconds = max(1, Int(retryAfter))
            return "Rate limited. You can try again in \(seconds) seconds."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .timeout:
            return "The request timed out. The AI provider may be slow. Try again or switch to a faster model."
        case .dnsFailure(let providerName):
            return "Cannot reach \(providerName). Check your internet connection."
        case .sslError:
            return "Secure connection failed. Check your network settings or try again later."
        case .modelUnavailable:
            return "The selected model is not available."
        case .contextLengthExceeded:
            return "Your input is too long for the selected model. Try shortening it or use a model with a larger context window."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .serviceUnavailable:
            return "The AI provider is experiencing issues. The service may be under maintenance. Try again in a moment."
        case .partialResponse:
            return "Connection lost during optimization. Partial result shown."
        case .responseTooLong:
            return "Response was unusually long and has been truncated."
        case .unknown(let message):
            return message
        case .noAPIKey:
            return "Please configure your API key in Settings (\u{2318},)."
        case .noNetwork:
            return "No internet connection. Check your network and try again."
        case .cancelled:
            return "Request cancelled."
        }
    }

    /// Whether this error suggests the user should check/update their API key in Settings.
    var isAPIKeyError: Bool {
        switch self {
        case .invalidAPIKey, .noAPIKey: return true
        default: return false
        }
    }

    /// Whether this error has partial output that can be displayed.
    var partialOutput: String? {
        switch self {
        case .partialResponse(let output): return output
        case .responseTooLong(let output): return output
        default: return nil
        }
    }
}

// MARK: - Network Error Classification

extension LLMError {
    /// Classifies a URLError into a specific LLMError case.
    static func classify(_ urlError: URLError, providerName: String) -> LLMError {
        switch urlError.code {
        case .timedOut:
            return .timeout
        case .dnsLookupFailed, .cannotFindHost:
            return .dnsFailure(providerName: providerName)
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateNotYetValid,
             .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .clientCertificateRejected, .clientCertificateRequired:
            return .sslError
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .noNetwork
        case .cannotConnectToHost:
            return .networkError(underlying: urlError)
        default:
            return .networkError(underlying: urlError)
        }
    }
}

// MARK: - Message Types

struct LLMMessage {
    enum Role: String {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String
}

struct LLMRequestParameters {
    let model: String
    let temperature: Double
    let maxTokens: Int
}

// MARK: - Model Info

struct LLMModelInfo: Identifiable {
    let id: String
    let displayName: String
    let contextWindow: Int
    let isDefault: Bool

    // Ollama-specific metadata
    var tags: [String] = []
    var parameterSize: String? = nil
    var isInstalled: Bool = true
    var isRecommended: Bool = false
    var bestFor: String? = nil
}

// MARK: - Provider Protocol

protocol LLMProviderProtocol {
    /// Display name shown in the UI (e.g. "Anthropic Claude").
    var displayName: String { get }

    /// SF Symbol name for the provider icon.
    var iconName: String { get }

    /// The provider type enum value.
    var providerType: LLMProvider { get }

    /// Send a prompt optimization request and receive a streamed response.
    func streamCompletion(
        messages: [LLMMessage],
        parameters: LLMRequestParameters
    ) -> AsyncThrowingStream<String, Error>

    /// Validate the API key by making a minimal API call.
    func validateAPIKey(_ key: String) async throws -> Bool

    /// List available models for this provider.
    func availableModels() async throws -> [LLMModelInfo]
}

// MARK: - Cloud Proxy Models Response

/// Shared Decodable for `/v1/claude-models` and `/v1/openai-models` cloud proxy responses.
struct CloudModelsResponse: Decodable {
    let models: [CloudModelEntry]
    let source: String?
    let fetchedAt: String?

    struct CloudModelEntry: Decodable {
        let id: String
        let displayName: String
        let contextWindow: Int
        let isDefault: Bool?
        let category: String?
    }
}
