import Foundation

final class LLMProviderManager {
    static let shared = LLMProviderManager()

    private let configurationService: ConfigurationService
    private let keychainService: KeychainService

    private lazy var claudeProvider = ClaudeProvider(keychainService: keychainService)
    private lazy var openAIProvider = OpenAIProvider(keychainService: keychainService)
    private lazy var ollamaProvider = OllamaProvider()
    private lazy var openRouterProvider = OpenRouterProvider(keychainService: keychainService)
    private lazy var cloudProvider = CloudProvider()

    init(
        configurationService: ConfigurationService = .shared,
        keychainService: KeychainService = .shared
    ) {
        self.configurationService = configurationService
        self.keychainService = keychainService
    }

    // MARK: - Active Provider

    /// Returns the currently active provider based on configuration.
    var activeProvider: LLMProviderProtocol {
        provider(for: configurationService.configuration.selectedProvider)
    }

    /// Returns the provider for a specific type.
    func provider(for type: LLMProvider) -> LLMProviderProtocol {
        switch type {
        case .anthropicClaude: return claudeProvider
        case .openAI: return openAIProvider
        case .ollama: return ollamaProvider
        case .openRouter: return openRouterProvider
        case .custom: return claudeProvider // Fallback to Claude for custom
        case .promptCraftCloud: return cloudProvider
        }
    }

    /// Switches the active provider.
    func switchProvider(to type: LLMProvider) {
        configurationService.update { $0.selectedProvider = type }
    }

    // MARK: - Provider Status

    struct ProviderStatus {
        let provider: LLMProvider
        let displayName: String
        let iconName: String
        let hasAPIKey: Bool
        let isActive: Bool
    }

    /// Returns the configuration status of all providers.
    func allProviderStatuses() -> [ProviderStatus] {
        let activeType = configurationService.configuration.selectedProvider
        return LLMProvider.allCases.compactMap { type -> ProviderStatus? in
            guard type != .custom else { return nil }
            // Only show Cloud when the user has a Cloud license
            if type == .promptCraftCloud && LicensingService.shared.licenseType != .cloud {
                return nil
            }
            let p = provider(for: type)
            let hasKey: Bool
            switch type {
            case .ollama:
                hasKey = true // Ollama doesn't need a key
            case .promptCraftCloud:
                hasKey = LicensingService.shared.licenseType == .cloud
            case .openRouter:
                hasKey = keychainService.hasAPIKey(for: .openRouter)
            default:
                hasKey = keychainService.hasAPIKey(for: type)
            }
            return ProviderStatus(
                provider: type,
                displayName: p.displayName,
                iconName: p.iconName,
                hasAPIKey: hasKey,
                isActive: type == activeType
            )
        }
    }

    /// Returns available models for the active provider.
    func availableModelsForActiveProvider() async throws -> [LLMModelInfo] {
        try await activeProvider.availableModels()
    }
}
