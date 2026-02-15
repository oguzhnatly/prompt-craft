import Foundation
import Security

/// Errors specific to Keychain operations.
enum KeychainError: LocalizedError {
    case accessDenied
    case unexpectedError(OSStatus)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Could not access Keychain. Check Keychain Access app settings."
        case .unexpectedError(let status):
            return "Keychain error (code \(status))."
        case .encodingFailed:
            return "Could not encode the API key."
        }
    }
}

final class KeychainService {
    static let shared = KeychainService()

    let serviceName: String

    private convenience init() {
        self.init(serviceName: AppConstants.bundleIdentifier)
    }

    init(serviceName: String) {
        self.serviceName = serviceName
    }

    // MARK: - Public API

    /// Save an API key for the given provider.
    /// Returns a descriptive error on failure rather than a plain Bool.
    @discardableResult
    func saveAPIKey(for provider: LLMProvider, key: String) -> Result<Void, KeychainError> {
        guard let data = key.data(using: .utf8) else {
            Logger.shared.error("Keychain: failed to encode API key for \(provider.rawValue)")
            return .failure(.encodingFailed)
        }

        // Delete existing key first
        _ = deleteAPIKey(for: provider)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: provider.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            Logger.shared.info("Keychain: saved API key for \(provider.rawValue)")
            return .success(())
        } else {
            let err = classifyStatus(status)
            Logger.shared.error("Keychain: failed to save API key for \(provider.rawValue), status \(status)")
            return .failure(err)
        }
    }

    /// Retrieve the API key for the given provider.
    func getAPIKey(for provider: LLMProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        if status != errSecSuccess {
            Logger.shared.warning("Keychain: failed to read API key for \(provider.rawValue), status \(status)")
            return nil
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func deleteAPIKey(for provider: LLMProvider) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: provider.rawValue,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func hasAPIKey(for provider: LLMProvider) -> Bool {
        return getAPIKey(for: provider) != nil
    }

    // MARK: - Private

    private func classifyStatus(_ status: OSStatus) -> KeychainError {
        switch status {
        case errSecAuthFailed, errSecInteractionNotAllowed:
            return .accessDenied
        default:
            return .unexpectedError(status)
        }
    }
}
