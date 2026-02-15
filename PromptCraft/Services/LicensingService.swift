import Foundation
import IOKit
import Security

// MARK: - Licensing Service
//
// Manages license validation and trial gating for PromptCraft.
// License keys are stored in the macOS Keychain.
// Validation uses Keygen.sh API for license key verification and machine activation.
//
// License types:
//   .pro   — One-time purchase, BYOK (bring your own API key)
//   .cloud — Subscription, includes PromptCraft Cloud AI provider
//
// Trial: 14 days from first launch, managed by TrialService.

// MARK: - Keygen Response Types

struct KeygenValidationResponse: Decodable {
    let meta: Meta
    let data: LicenseData?

    struct Meta: Decodable {
        let valid: Bool
        let detail: String
        let code: String
    }

    struct LicenseData: Decodable {
        let id: String
        let attributes: Attrs
    }

    struct Attrs: Decodable {
        let key: String
        let expiry: String?
        let status: String
        let metadata: [String: String]?
    }
}

struct KeygenMachineResponse: Decodable {
    let data: MData

    struct MData: Decodable {
        let id: String
    }
}

final class LicensingService: ObservableObject {
    static let shared = LicensingService()

    // MARK: - Published State

    @Published private(set) var isProUser: Bool = false
    @Published private(set) var licenseType: LicenseType?
    @Published private(set) var licenseKey: String?
    @Published private(set) var licenseEmail: String?
    @Published private(set) var validationError: String?
    @Published private(set) var isValidating: Bool = false
    @Published private(set) var activationDate: Date?
    @Published private(set) var lastValidationDate: Date?
    @Published private(set) var machineID: String?

    // MARK: - Dependencies

    private let trialService = TrialService.shared
    private let defaults = UserDefaults.standard

    // MARK: - Keychain Constants

    private let keychainService = AppConstants.bundleIdentifier
    private let keychainAccountLicense = "com.promptcraft.license"
    private let keychainAccountMachine = "com.promptcraft.machine"

    // MARK: - Validation Intervals

    /// Re-validate Pro license every 7 days.
    private let proRevalidationInterval: TimeInterval = 7 * 24 * 60 * 60

    /// Re-validate Cloud license every 24 hours.
    private let cloudRevalidationInterval: TimeInterval = 24 * 60 * 60

    /// Offline grace period: 72 hours from last successful validation.
    private let offlineGracePeriod: TimeInterval = 72 * 60 * 60

    // MARK: - Init

    private init() {
        // Load saved machine ID from UserDefaults
        machineID = defaults.string(forKey: AppConstants.UserDefaultsKeys.machineID)

        // Load saved license key from Keychain on init
        if let savedKey = readKeychainLicenseKey(), !savedKey.isEmpty {
            licenseKey = savedKey

            // Load cached validation result
            if let cached = loadCachedValidation() {
                isProUser = cached.isValid
                licenseType = cached.licenseType
                licenseEmail = cached.email
                activationDate = cached.activationDate
                lastValidationDate = cached.validationDate
                if let cachedMachine = cached.machineID {
                    machineID = cachedMachine
                }

                // Update trial state to match
                if isProUser {
                    let state: TrialState = licenseType == .cloud ? .cloud : .pro
                    trialService.setLicensedState(state)
                }
            } else {
                // No cache — trust saved key until re-validation
                isProUser = true
            }
        }
    }

    // MARK: - Computed Properties

    /// Whether the user can perform an optimization right now.
    var canOptimize: Bool {
        isProUser || trialService.isTrialActive
    }

    /// Convenience: whether the user has an active paid license.
    var isPaid: Bool { isProUser }

    // MARK: - Machine Fingerprint

    /// Returns the IOPlatformUUID from IOKit, falling back to hostname.
    private func machineFingerprint() -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(service) }
        guard let uuid = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            return ProcessInfo.processInfo.hostName
        }
        return uuid
    }

    // MARK: - License Validation

    /// Validate a license key against the Keygen.sh API.
    @discardableResult
    func validateLicense(key: String) async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await MainActor.run {
                validationError = "Please enter a license key."
                isProUser = false
            }
            return false
        }

        await MainActor.run { isValidating = true }

        let fingerprint = machineFingerprint()

        // Build validation request to Keygen.sh
        guard let url = URL(string: AppConstants.KeygenAPI.validateURL) else {
            await MainActor.run {
                isValidating = false
                validationError = "Invalid validation URL."
            }
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        request.setValue("License \(trimmed)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "meta": [
                "key": trimmed,
                "scope": [
                    "fingerprint": fingerprint
                ]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                await handleOfflineGrace()
                await MainActor.run { isValidating = false }
                return isProUser
            }

            guard (200...499).contains(httpResponse.statusCode) else {
                await handleOfflineGrace()
                await MainActor.run { isValidating = false }
                return isProUser
            }

            let decoded = try JSONDecoder().decode(KeygenValidationResponse.self, from: data)
            let code = decoded.meta.code

            switch code {
            case "VALID":
                let tier = decoded.data?.attributes.metadata?["tier"]
                let email = decoded.data?.attributes.metadata?["email"]
                let detectedType: LicenseType = tier == "cloud" ? .cloud : .pro

                await MainActor.run {
                    isValidating = false
                    self.licenseKey = trimmed
                    self.licenseType = detectedType
                    self.isProUser = true
                    self.validationError = nil
                    self.licenseEmail = email ?? self.licenseEmail
                    self.activationDate = self.activationDate ?? Date()
                    self.lastValidationDate = Date()

                    // Clear any offline grace start
                    defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.offlineGraceStart)

                    // Store in Keychain
                    writeKeychainLicenseKey(trimmed)

                    // Cache validation result
                    cacheValidation(CachedValidation(
                        isValid: true,
                        licenseType: detectedType,
                        email: self.licenseEmail,
                        activationDate: self.activationDate ?? Date(),
                        validationDate: Date(),
                        machineID: self.machineID
                    ))

                    // Update trial state
                    let state: TrialState = detectedType == .cloud ? .cloud : .pro
                    self.trialService.setLicensedState(state)

                    // If Cloud, auto-configure the provider
                    if detectedType == .cloud {
                        ConfigurationService.shared.update { $0.selectedProvider = .promptCraftCloud }
                    }

                    NotificationCenter.default.post(name: AppConstants.Notifications.licenseStateChanged, object: nil)
                }
                return true

            case "NO_MACHINE", "NO_MACHINES", "FINGERPRINT_SCOPE_MISMATCH":
                // Need to activate this machine first
                if let licenseID = decoded.data?.id {
                    let activated = await activateMachine(
                        licenseKey: trimmed,
                        licenseID: licenseID,
                        fingerprint: fingerprint
                    )
                    if activated {
                        // Re-validate after machine activation
                        await MainActor.run { isValidating = false }
                        return await validateLicense(key: trimmed)
                    } else {
                        await MainActor.run {
                            isValidating = false
                            validationError = "Activated on too many devices. Deactivate one first."
                        }
                        return false
                    }
                }
                await MainActor.run {
                    isValidating = false
                    validationError = "Unable to activate machine."
                }
                return false

            case "TOO_MANY_MACHINES":
                await MainActor.run {
                    isValidating = false
                    validationError = "Activated on 3 devices. Deactivate one first."
                }
                return false

            case "EXPIRED":
                await MainActor.run {
                    isValidating = false
                    validationError = "License expired."
                    isProUser = false
                }
                return false

            case "SUSPENDED":
                await MainActor.run {
                    isValidating = false
                    validationError = "License suspended."
                    isProUser = false
                }
                return false

            case "OVERDUE":
                await MainActor.run {
                    isValidating = false
                    validationError = "Payment overdue."
                    isProUser = false
                }
                return false

            default:
                await MainActor.run {
                    isValidating = false
                    validationError = "Invalid license key."
                    isProUser = false
                }
                return false
            }
        } catch {
            // Network error — use offline grace period
            await handleOfflineGrace()
            await MainActor.run { isValidating = false }
            return isProUser
        }
    }

    // MARK: - Machine Activation

    /// Activate this machine for the given license via Keygen.sh.
    private func activateMachine(
        licenseKey: String,
        licenseID: String,
        fingerprint: String
    ) async -> Bool {
        guard let url = URL(string: AppConstants.KeygenAPI.machinesURL) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        request.setValue("License \(licenseKey)", forHTTPHeaderField: "Authorization")

        let macName = Host.current().localizedName ?? "Mac"
        let body: [String: Any] = [
            "data": [
                "type": "machines",
                "attributes": [
                    "fingerprint": fingerprint,
                    "name": macName
                ],
                "relationships": [
                    "license": [
                        "data": [
                            "type": "licenses",
                            "id": licenseID
                        ]
                    ]
                ]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return false }

            if httpResponse.statusCode == 201 {
                // Machine created
                let decoded = try JSONDecoder().decode(KeygenMachineResponse.self, from: data)
                let newMachineID = decoded.data.id

                await MainActor.run {
                    self.machineID = newMachineID
                    defaults.set(newMachineID, forKey: AppConstants.UserDefaultsKeys.machineID)
                    writeKeychainValue(newMachineID, account: keychainAccountMachine)
                }
                return true
            }

            // 422 likely means too many machines
            return false
        } catch {
            return false
        }
    }

    // MARK: - Activation

    /// Activate a license key (validate + store).
    @discardableResult
    func activateLicense(key: String) async -> Bool {
        return await validateLicense(key: key)
    }

    // MARK: - Deactivation

    /// Remove the current license and return to trial state.
    func deactivateLicense() {
        // Fire-and-forget: deactivate machine on Keygen.sh
        if let currentMachineID = machineID, let currentKey = licenseKey {
            let machineURL = AppConstants.KeygenAPI.machinesURL + "/\(currentMachineID)"
            if let url = URL(string: machineURL) {
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
                request.setValue("License \(currentKey)", forHTTPHeaderField: "Authorization")

                Task {
                    _ = try? await URLSession.shared.data(for: request)
                }
            }
        }

        // Clear machine ID from Keychain and UserDefaults
        deleteKeychainValue(account: keychainAccountMachine)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.machineID)

        // Clear license
        deleteKeychainLicenseKey()
        clearCachedValidation()
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.offlineGraceStart)

        licenseKey = nil
        licenseType = nil
        licenseEmail = nil
        isProUser = false
        validationError = nil
        activationDate = nil
        lastValidationDate = nil
        machineID = nil

        // Recalculate trial state
        trialService.checkTrialStatus()

        NotificationCenter.default.post(name: AppConstants.Notifications.licenseStateChanged, object: nil)
    }

    // MARK: - Periodic Re-validation

    /// Called periodically to re-validate the license if stale.
    func revalidateIfNeeded() {
        guard let key = licenseKey, isProUser else { return }

        let interval = licenseType == .cloud ? cloudRevalidationInterval : proRevalidationInterval
        let lastCheck = lastValidationDate ?? .distantPast
        if Date().timeIntervalSince(lastCheck) >= interval {
            Task {
                await validateLicense(key: key)
            }
        }
    }

    // MARK: - Offline Grace Period

    /// Handle offline scenario: allow continued use within 72-hour grace period.
    private func handleOfflineGrace() async {
        guard let lastValidation = lastValidationDate else {
            // Never validated — cannot grant grace
            await MainActor.run {
                validationError = "Network error. Please check your connection."
                isProUser = false
            }
            return
        }

        let elapsed = Date().timeIntervalSince(lastValidation)
        if elapsed < offlineGracePeriod {
            // Within grace period — keep current state
            await MainActor.run {
                validationError = nil
            }
        } else {
            // Grace period expired
            await MainActor.run {
                validationError = "Offline for too long. Please connect to re-validate your license."
                isProUser = false
            }
        }
    }

    // MARK: - Keychain Helpers

    private func writeKeychainLicenseKey(_ key: String) {
        writeKeychainValue(key, account: keychainAccountLicense)
    }

    private func readKeychainLicenseKey() -> String? {
        return readKeychainValue(account: keychainAccountLicense)
    }

    private func deleteKeychainLicenseKey() {
        deleteKeychainValue(account: keychainAccountLicense)
    }

    private func writeKeychainValue(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func readKeychainValue(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }

        return value
    }

    private func deleteKeychainValue(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Cached Validation

    private struct CachedValidation: Codable {
        let isValid: Bool
        let licenseType: LicenseType?
        let email: String?
        let activationDate: Date
        let validationDate: Date
        let machineID: String?
    }

    private func cacheValidation(_ result: CachedValidation) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        // Simple obfuscation: base64 encode
        let encoded = data.base64EncodedString()
        defaults.set(encoded, forKey: AppConstants.UserDefaultsKeys.licenseCachedResult)
        defaults.set(result.validationDate.timeIntervalSince1970, forKey: AppConstants.UserDefaultsKeys.licenseLastValidated)
    }

    private func loadCachedValidation() -> CachedValidation? {
        guard let encoded = defaults.string(forKey: AppConstants.UserDefaultsKeys.licenseCachedResult),
              let data = Data(base64Encoded: encoded),
              let cached = try? JSONDecoder().decode(CachedValidation.self, from: data)
        else { return nil }
        return cached
    }

    private func clearCachedValidation() {
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.licenseCachedResult)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.licenseLastValidated)
    }
}
