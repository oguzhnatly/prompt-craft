import Combine
import Foundation
import Security

// MARK: - TrialService

final class TrialService: ObservableObject {
    static let shared = TrialService()

    @Published private(set) var trialState: TrialState = .active(daysRemaining: 14)
    @Published private(set) var daysRemaining: Int = 14
    @Published private(set) var trialStartDate: Date?

    private let defaults = UserDefaults.standard
    private let trialDuration = 14

    /// XOR constant for obfuscating the timestamp in UserDefaults.
    private let xorKey: UInt64 = 0xA3F1_C7D2_E5B9_4608

    /// Tolerance in seconds when comparing dates across stores (60s).
    private let dateTolerance: TimeInterval = 60.0

    // MARK: - Keychain Constants

    private let keychainAccount = "com.promptcraft.trial.anchor"
    private let keychainService = AppConstants.bundleIdentifier

    // MARK: - Marker File

    private var markerFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PromptCraft")
            .appendingPathComponent(".session_cache")
    }

    // MARK: - Init

    private init() {
        checkTrialStatus()
    }

    // MARK: - Public API

    /// Begin a 14-day trial, recording the start date to all 3 stores.
    func startTrial() {
        let now = Date()
        writeUserDefaults(date: now)
        writeMarkerFile(date: now)
        writeKeychain(date: now)
        trialStartDate = now
        checkTrialStatus()
        NotificationCenter.default.post(name: AppConstants.Notifications.trialStateChanged, object: nil)
    }

    /// Recalculate trial state from stored data and update published properties.
    func checkTrialStatus() {
        // If the user is licensed, state is set externally
        if case .pro = trialState { return }
        if case .cloud = trialState { return }

        guard let startDate = resolvedStartDate() else {
            // No trial has been started yet — treat as fresh (14 days).
            trialStartDate = nil
            daysRemaining = trialDuration
            trialState = .active(daysRemaining: trialDuration)
            return
        }

        trialStartDate = startDate
        let elapsed = Calendar.current.dateComponents([.day], from: startDate, to: Date())
        let daysPassed = max(0, elapsed.day ?? 0)
        let remaining = max(0, trialDuration - daysPassed)

        daysRemaining = remaining
        trialState = remaining > 0 ? .active(daysRemaining: remaining) : .expired

        NotificationCenter.default.post(name: AppConstants.Notifications.trialStateChanged, object: nil)
    }

    /// Set trial state directly (used by LicensingService on activation/deactivation).
    func setLicensedState(_ state: TrialState) {
        trialState = state
        if case .active(let days) = state {
            daysRemaining = days
        }
    }

    var isTrialActive: Bool {
        switch trialState {
        case .active: return true
        default: return false
        }
    }

    var isExpired: Bool {
        trialState == .expired
    }

    /// Show upgrade nudge when 4 or fewer days remain.
    var shouldShowNudge: Bool {
        switch trialState {
        case .active(let days): return days <= 4
        default: return trialState == .expired
        }
    }

    /// Show warning banner when 1 or fewer days remain.
    var shouldShowWarning: Bool {
        switch trialState {
        case .active(let days): return days <= 1
        default: return trialState == .expired
        }
    }

    // MARK: - Context Stats Helpers

    var contextEntryCount: Int {
        ContextEngineService.shared.entryCount
    }

    var clusterCount: Int {
        ContextEngineService.shared.clusters.count
    }

    // MARK: - Resolved Start Date (Consensus)

    /// Resolve the trial start date by taking a consensus of available stores.
    /// At least 2 sources must agree (within tolerance) for the date to be trusted.
    func resolvedStartDate() -> Date? {
        var dates: [Date] = []

        if let d = readUserDefaults() { dates.append(d) }
        if let d = readMarkerFile() { dates.append(d) }
        if let d = readKeychain() { dates.append(d) }

        guard !dates.isEmpty else { return nil }

        // If only one source, trust it
        if dates.count == 1 { return dates[0] }

        // Find the pair with the smallest difference
        var bestDate: Date?
        var bestDiff: TimeInterval = .greatestFiniteMagnitude

        for i in 0..<dates.count {
            for j in (i + 1)..<dates.count {
                let diff = abs(dates[i].timeIntervalSince(dates[j]))
                if diff < bestDiff {
                    bestDiff = diff
                    // Take the earlier date as the canonical one
                    bestDate = min(dates[i], dates[j])
                }
            }
        }

        // Accept if within tolerance
        if bestDiff <= dateTolerance {
            // Heal any missing stores
            if let date = bestDate {
                healStores(date: date)
            }
            return bestDate
        }

        // Disagreement: take the earliest available (conservative)
        let earliest = dates.min()
        if let date = earliest {
            healStores(date: date)
        }
        return earliest
    }

    /// Re-write any missing stores to maintain redundancy.
    private func healStores(date: Date) {
        if readUserDefaults() == nil { writeUserDefaults(date: date) }
        if readMarkerFile() == nil { writeMarkerFile(date: date) }
        if readKeychain() == nil { writeKeychain(date: date) }
    }

    // MARK: - Store 1: UserDefaults (XOR-obfuscated)

    private func writeUserDefaults(date: Date) {
        let timestamp = UInt64(bitPattern: Int64(date.timeIntervalSince1970))
        let obfuscated = timestamp ^ xorKey
        defaults.set(Double(bitPattern: obfuscated), forKey: AppConstants.UserDefaultsKeys.trialCachePolicy)
    }

    private func readUserDefaults() -> Date? {
        let raw = defaults.double(forKey: AppConstants.UserDefaultsKeys.trialCachePolicy)
        guard raw != 0 else { return nil }
        let obfuscated = raw.bitPattern
        let timestamp = obfuscated ^ xorKey
        let interval = TimeInterval(Int64(bitPattern: timestamp))
        guard interval > 0 && interval < Date().timeIntervalSince1970 + 86400 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    // MARK: - Store 2: Marker File (Base64 JSON + checksum)

    private struct MarkerData: Codable {
        let timestamp: TimeInterval
        let checksum: String
    }

    private func writeMarkerFile(date: Date) {
        guard let fileURL = markerFileURL else { return }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let ts = date.timeIntervalSince1970
        let checksumInput = "pc_\(Int(ts))_trial"
        let checksum = simpleHash(checksumInput)
        let marker = MarkerData(timestamp: ts, checksum: checksum)

        guard let jsonData = try? JSONEncoder().encode(marker) else { return }
        let encoded = jsonData.base64EncodedData()
        try? encoded.write(to: fileURL)
    }

    private func readMarkerFile() -> Date? {
        guard let fileURL = markerFileURL,
              let encodedData = try? Data(contentsOf: fileURL),
              let jsonData = Data(base64Encoded: encodedData),
              let marker = try? JSONDecoder().decode(MarkerData.self, from: jsonData)
        else { return nil }

        // Verify checksum
        let checksumInput = "pc_\(Int(marker.timestamp))_trial"
        guard simpleHash(checksumInput) == marker.checksum else { return nil }

        let interval = marker.timestamp
        guard interval > 0 && interval < Date().timeIntervalSince1970 + 86400 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    // MARK: - Store 3: Keychain

    private func writeKeychain(date: Date) {
        let data = "\(date.timeIntervalSince1970)".data(using: .utf8)!

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func readKeychain() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8),
              let interval = TimeInterval(str),
              interval > 0 && interval < Date().timeIntervalSince1970 + 86400
        else { return nil }

        return Date(timeIntervalSince1970: interval)
    }

    // MARK: - Simple Hash

    private func simpleHash(_ input: String) -> String {
        var hash: UInt64 = 5381
        for char in input.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(char)
        }
        return String(hash, radix: 16)
    }
}
