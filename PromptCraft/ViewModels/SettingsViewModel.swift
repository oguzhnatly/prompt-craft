import AppKit
import Combine
import ServiceManagement
import UniformTypeIdentifiers

final class SettingsViewModel: ObservableObject {

    // MARK: - API Key State

    @Published var apiKeyText: String = ""
    @Published var isKeyVisible: Bool = false
    @Published var validationState: ValidationState = .idle

    // MARK: - Model State

    @Published var availableModels: [LLMModelInfo] = []
    @Published var isLoadingModels: Bool = false
    @Published var modelDownloadProgress: Double? = nil  // nil = not downloading, 0..1 = progress
    @Published var modelDownloadStatus: String? = nil
    @Published var downloadingModelName: String? = nil
    private var modelDownloadTask: Task<Void, Never>?

    // MARK: - UI State

    @Published var showAdvancedLLM: Bool = false
    @Published var showClearHistoryConfirmation: Bool = false
    @Published var showResetConfirmation: Bool = false
    @Published var showClearContextConfirmation: Bool = false

    enum ValidationState: Equatable {
        case idle
        case validating
        case valid
        case invalid(String)
    }

    // MARK: - Services

    private let configService = ConfigurationService.shared
    private let keychainService = KeychainService.shared
    private let historyService = HistoryService.shared
    private let providerManager = LLMProviderManager.shared
    private let contextEngine = ContextEngineService.shared

    var historyCount: Int { historyService.entries.count }

    // MARK: - API Key

    func loadAPIKey(for provider: LLMProvider) {
        isKeyVisible = false
        validationState = .idle
        if provider == .ollama || provider == .promptCraftCloud {
            apiKeyText = ""
            return
        }
        apiKeyText = keychainService.getAPIKey(for: provider) ?? ""
    }

    func saveAPIKey(for provider: LLMProvider) {
        guard provider != .ollama && provider != .promptCraftCloud else { return }
        let trimmed = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            keychainService.deleteAPIKey(for: provider)
        } else {
            let result = keychainService.saveAPIKey(for: provider, key: trimmed)
            if case .failure(let error) = result {
                validationState = .invalid(error.localizedDescription)
            }
        }
    }

    func validateAPIKey(for provider: LLMProvider) {
        if provider == .ollama {
            testOllamaConnection()
            return
        }

        let key = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            validationState = .invalid("Please enter an API key.")
            return
        }

        validationState = .validating
        saveAPIKey(for: provider)

        Task { @MainActor in
            do {
                let p = self.providerManager.provider(for: provider)
                let isValid = try await p.validateAPIKey(key)
                self.validationState = isValid ? .valid : .invalid("Invalid API key.")
            } catch {
                self.validationState = .invalid(error.localizedDescription)
            }
        }
    }

    func testOllamaConnection() {
        validationState = .validating
        Task { @MainActor in
            do {
                let p = self.providerManager.provider(for: .ollama)
                let isValid = try await p.validateAPIKey("")
                self.validationState = isValid ? .valid : .invalid("Could not connect.")
            } catch {
                let port = ConfigurationService.shared.configuration.ollamaPort
                self.validationState = .invalid("Ollama not reachable at localhost:\(port)")
            }
        }
    }

    // MARK: - Models

    func loadModels(for provider: LLMProvider) {
        isLoadingModels = true
        availableModels = []
        Task { @MainActor in
            do {
                let p = self.providerManager.provider(for: provider)
                self.availableModels = try await p.availableModels()
            } catch {
                self.availableModels = []
            }
            self.isLoadingModels = false
            self.autoSelectModelIfNeeded(for: provider)
        }
    }

    /// If no model is selected or the selected model isn't available, pick the best default.
    private func autoSelectModelIfNeeded(for provider: LLMProvider) {
        let current = configService.configuration.selectedModelName
        let installedModels = availableModels.filter(\.isInstalled)

        // Check if current selection is valid among installed models
        let currentIsValid = installedModels.contains { $0.id == current }

        if !currentIsValid {
            // Pick first installed recommended, or first installed, or first catalog entry
            if let recommended = installedModels.first(where: \.isRecommended) {
                configService.update { $0.selectedModelName = recommended.id }
            } else if let firstInstalled = installedModels.first {
                configService.update { $0.selectedModelName = firstInstalled.id }
            } else if let firstModel = availableModels.first {
                configService.update { $0.selectedModelName = firstModel.id }
            }
        }
    }

    /// Pull/download an Ollama model. On completion, reloads models and selects it.
    func pullOllamaModel(name: String) {
        guard downloadingModelName == nil else { return } // One at a time

        downloadingModelName = name
        modelDownloadProgress = 0
        modelDownloadStatus = "Starting download..."

        modelDownloadTask = Task { @MainActor in
            do {
                let ollamaProvider = self.providerManager.provider(for: .ollama) as! OllamaProvider
                for try await progress in ollamaProvider.pullModel(name: name) {
                    if Task.isCancelled { throw CancellationError() }
                    self.modelDownloadProgress = progress.fraction
                    if progress.isDownloading {
                        if progress.total > 0 {
                            self.modelDownloadStatus = "Downloading \(Self.formatBytes(progress.completed)) / \(Self.formatBytes(progress.total))"
                        } else {
                            self.modelDownloadStatus = "Preparing download..."
                        }
                    } else if progress.status.contains("verifying") {
                        self.modelDownloadProgress = nil // indeterminate
                        self.modelDownloadStatus = "Verifying integrity..."
                    } else if progress.status.contains("writing") {
                        self.modelDownloadProgress = nil
                        self.modelDownloadStatus = "Writing model to disk..."
                    } else if progress.status == "success" {
                        self.modelDownloadStatus = "Download complete!"
                    } else if !progress.status.isEmpty {
                        self.modelDownloadStatus = progress.status.prefix(1).uppercased() + progress.status.dropFirst()
                    }
                }

                // Done — reload models and select
                self.modelDownloadProgress = nil
                self.modelDownloadStatus = nil
                self.downloadingModelName = nil
                self.loadModels(for: .ollama)

                // Select the newly downloaded model
                self.configService.update { $0.selectedModelName = name }
            } catch is CancellationError {
                self.modelDownloadProgress = nil
                self.modelDownloadStatus = "Download cancelled"
                self.downloadingModelName = nil
                self.modelDownloadTask = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if self.downloadingModelName == nil { self.modelDownloadStatus = nil }
                }
            } catch {
                self.modelDownloadProgress = nil
                self.modelDownloadStatus = "Download failed: \(error.localizedDescription)"
                self.downloadingModelName = nil
                self.modelDownloadTask = nil

                // Clear error after a few seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    if self.downloadingModelName == nil {
                        self.modelDownloadStatus = nil
                    }
                }
            }
        }
    }

    /// Cancel an in-progress model download.
    func cancelModelDownload() {
        modelDownloadTask?.cancel()
        modelDownloadTask = nil
    }

    /// Delete a locally installed Ollama model, then reload the model list.
    @Published var isDeletingModel: Bool = false

    func deleteOllamaModel(name: String) {
        guard !isDeletingModel else { return }
        isDeletingModel = true

        Task { @MainActor in
            do {
                let ollamaProvider = self.providerManager.provider(for: .ollama) as! OllamaProvider
                try await ollamaProvider.deleteModel(name: name)

                // If the deleted model was selected, clear selection so autoSelect picks a new one
                if self.configService.configuration.selectedModelName == name {
                    self.configService.update { $0.selectedModelName = "" }
                }

                self.loadModels(for: .ollama)
            } catch {
                self.modelDownloadStatus = "Delete failed: \(error.localizedDescription)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    if self.downloadingModelName == nil { self.modelDownloadStatus = nil }
                }
            }
            self.isDeletingModel = false
        }
    }

    /// Format byte count as human-readable string (e.g. "4.9 GB" or "128 MB").
    private static func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    // MARK: - Data Management

    func clearHistory() {
        historyService.clearAll()
        showClearHistoryConfirmation = false
    }

    func resetAllSettings() {
        configService.resetToDefaults()
        apiKeyText = ""
        isKeyVisible = false
        validationState = .idle
        showAdvancedLLM = false
        showResetConfirmation = false
        OnboardingManager.shared.resetOnboarding()
        NotificationCenter.default.post(name: AppConstants.Notifications.resetAllSettings, object: nil)
    }

    func exportConfiguration() {
        guard let data = configService.exportAsJSON() else { return }

        lockPopover(true)
        defer { lockPopover(false) }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PromptCraft-config.json"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    func importConfiguration() {
        lockPopover(true)
        defer { lockPopover(false) }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            if configService.importFromJSON(data) {
                loadAPIKey(for: configService.configuration.selectedProvider)
                loadModels(for: configService.configuration.selectedProvider)
            }
        }
    }

    // MARK: - Context Engine

    func reclusterContext() {
        contextEngine.recluster()
    }

    func clearContextData() {
        contextEngine.clearAllData()
        showClearContextConfirmation = false
    }

    @discardableResult
    func renameContextProject(clusterID: UUID, to newName: String) -> Bool {
        contextEngine.renameCluster(clusterID: clusterID, to: newName)
    }

    // MARK: - Launch at Login

    func setLaunchAtLogin(_ enabled: Bool) {
        configService.update { $0.launchAtLogin = enabled }
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Revert on failure
                configService.update { $0.launchAtLogin = !enabled }
            }
        }
    }

    // MARK: - Helpers

    var apiKeyHelperURL: URL? {
        switch configService.configuration.selectedProvider {
        case .anthropicClaude:
            return URL(string: "https://console.anthropic.com/settings/keys")
        case .openAI:
            return URL(string: "https://platform.openai.com/api-keys")
        default:
            return nil
        }
    }

    var apiKeyHelperText: String {
        switch configService.configuration.selectedProvider {
        case .anthropicClaude:
            return "Get your API key at console.anthropic.com"
        case .openAI:
            return "Get your API key at platform.openai.com"
        default:
            return ""
        }
    }

    private func lockPopover(_ locked: Bool) {
        NotificationCenter.default.post(
            name: AppConstants.Notifications.lockPopover,
            object: nil,
            userInfo: ["locked": locked]
        )
    }
}
