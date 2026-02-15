import Combine
import Foundation

final class ConfigurationService: ObservableObject {
    static let shared = ConfigurationService()

    @Published private(set) var configuration: AppConfiguration

    private let defaults: UserDefaults
    private let configKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cancellables = Set<AnyCancellable>()

    private convenience init() {
        self.init(defaults: .standard, configKey: AppConstants.UserDefaultsKeys.appConfiguration)
    }

    init(defaults: UserDefaults, configKey: String) {
        self.defaults = defaults
        self.configKey = configKey

        if let data = defaults.data(forKey: configKey),
           let loaded = try? JSONDecoder().decode(AppConfiguration.self, from: data) {
            self.configuration = loaded
            Logger.shared.info("Configuration loaded from UserDefaults")
        } else {
            self.configuration = .default
            Logger.shared.info("Using default configuration")
        }

        // Auto-save whenever configuration changes
        $configuration
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] newConfig in
                self?.persist(newConfig)
            }
            .store(in: &cancellables)
    }

    // MARK: - Update

    func update(_ transform: (inout AppConfiguration) -> Void) {
        var config = configuration
        transform(&config)
        configuration = config
    }

    // MARK: - Reset

    func resetToDefaults() {
        configuration = .default
        KeychainService.shared.deleteAPIKey(for: .anthropicClaude)
        KeychainService.shared.deleteAPIKey(for: .openAI)
        KeychainService.shared.deleteAPIKey(for: .ollama)
        KeychainService.shared.deleteAPIKey(for: .custom)
        Logger.shared.info("All settings reset to defaults")
    }

    // MARK: - Export / Import

    func exportAsJSON() -> Data? {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(configuration)
    }

    func importFromJSON(_ data: Data) -> Bool {
        do {
            let imported = try decoder.decode(AppConfiguration.self, from: data)
            configuration = imported
            Logger.shared.info("Configuration imported successfully")
            return true
        } catch {
            Logger.shared.error("Failed to import configuration", error: error)
            return false
        }
    }

    // MARK: - Private

    private func persist(_ config: AppConfiguration) {
        do {
            let data = try encoder.encode(config)
            defaults.set(data, forKey: configKey)
        } catch {
            Logger.shared.error("Failed to persist configuration", error: error)
        }
    }
}
