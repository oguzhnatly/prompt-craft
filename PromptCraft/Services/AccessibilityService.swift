import AppKit
import ApplicationServices
import Combine

/// Represents the current state of accessibility permission detection.
enum AccessibilityPermissionState: Equatable {
    case notGranted
    case checking
    case granted
    case needsRestart
}

final class AccessibilityService: ObservableObject {
    static let shared = AccessibilityService()

    private let defaults = UserDefaults.standard
    private let dialogShownKey = AppConstants.UserDefaultsKeys.accessibilityDialogShown

    /// The current permission state, published for SwiftUI binding.
    @Published private(set) var permissionState: AccessibilityPermissionState = .notGranted

    /// Whether accessibility is functionally available right now.
    var isAccessibilityGranted: Bool {
        permissionState == .granted
    }

    /// Whether we're running inside Xcode's debugger (DerivedData path or Xcode env vars).
    private(set) var isXcodeDebugMode: Bool = false

    private var pollingTimer: Timer?
    private var pollingAttempt = 0
    private let pollingIntervals: [TimeInterval] = [2, 2, 4, 4, 8]

    private var periodicCheckTimer: Timer?

    private init() {
        detectXcodeDebugMode()
        detectSandboxInDebug()
        updatePermissionStateSilently()
    }

    // MARK: - Multi-Layer Permission Detection

    /// Probe using CGEventTap with `.defaultTap` option.
    /// `.defaultTap` requires Accessibility permission (not Input Monitoring).
    /// `.listenOnly` would require Input Monitoring instead — wrong permission type.
    private func probeWithEventTap() -> Bool {
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )

        if let tap {
            CFMachPortInvalidate(tap)
            return true
        }
        return false
    }

    /// Combined multi-layer check:
    /// 1. AXIsProcessTrustedWithOptions (standard API, prompt disabled)
    /// 2. CGEventTap .defaultTap probe (functional test of the actual API)
    func isAccessibilityActuallyGranted() -> Bool {
        // Primary: AXIsProcessTrustedWithOptions with prompt disabled.
        // This is the standard API used by apps like alt-tab-macos.
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts) {
            return true
        }
        // Secondary: CGEventTap probe — exercises the actual API in case TCC cache is stale.
        return probeWithEventTap()
    }

    /// Silently update the permission state without UI side-effects.
    /// Does not overwrite `.checking` or `.needsRestart` states unless permission is now granted.
    func updatePermissionStateSilently() {
        let granted = isAccessibilityActuallyGranted()

        if granted {
            if permissionState != .granted {
                stopPolling()
                permissionState = .granted
                NotificationCenter.default.post(
                    name: AppConstants.Notifications.accessibilityStateChanged,
                    object: nil,
                    userInfo: ["granted": true]
                )
            }
        } else {
            // Only update to .notGranted if we're not in a transient state (checking/needsRestart)
            if permissionState == .granted {
                permissionState = .notGranted
                NotificationCenter.default.post(
                    name: AppConstants.Notifications.accessibilityStateChanged,
                    object: nil,
                    userInfo: ["granted": false]
                )
            }
        }
    }

    /// Perform a full re-check and update the published state.
    func recheckPermission() {
        updatePermissionStateSilently()
    }

    // MARK: - Polling After Grant

    /// Start polling for permission changes after the user clicks "Grant Access".
    func startPollingForPermission() {
        stopPolling()
        pollingAttempt = 0
        permissionState = .checking
        scheduleNextPoll()
    }

    /// Stop any active polling timer.
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func scheduleNextPoll() {
        guard pollingAttempt < pollingIntervals.count else {
            // Exhausted polling — permission didn't update live. Suggest restart.
            permissionState = .needsRestart
            return
        }

        let interval = pollingIntervals[pollingAttempt]
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.pollCheck()
        }
    }

    private func pollCheck() {
        if isAccessibilityActuallyGranted() {
            permissionState = .granted
            stopPolling()
            NotificationCenter.default.post(
                name: AppConstants.Notifications.accessibilityStateChanged,
                object: nil,
                userInfo: ["granted": true]
            )
            return
        }

        pollingAttempt += 1
        scheduleNextPoll()
    }

    // MARK: - Request & Open Settings

    /// Request accessibility access if not already granted.
    /// Shows a one-time explanatory dialog, then opens System Settings.
    func requestAccessibilityIfNeeded() {
        guard !isAccessibilityGranted else { return }
        guard !defaults.bool(forKey: dialogShownKey) else { return }

        defaults.set(true, forKey: dialogShownKey)

        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = """
            PromptCraft needs accessibility access to register global keyboard shortcuts \
            and show the inline overlay on text fields. \
            This allows you to activate PromptCraft from any app with \
            \(ConfigurationService.shared.configuration.globalShortcut.displayString) \
            and optimize text directly where you type.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
            startPollingForPermission()
        }
    }

    /// Open System Settings > Privacy & Security > Accessibility.
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Xcode Debug Mode Detection

    private func detectXcodeDebugMode() {
        let executablePath = Bundle.main.executablePath ?? ""
        let env = ProcessInfo.processInfo.environment

        let isDerivedData = executablePath.contains("DerivedData")
        let hasXcodeEnv = env["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil
            || env["XCODE_VERSION_ACTUAL"] != nil
            || env["__CFBundleIdentifier"] == "com.apple.dt.Xcode"

        isXcodeDebugMode = isDerivedData || hasXcodeEnv
    }

    // MARK: - Sandbox & Signing Verification

    private func detectSandboxInDebug() {
        #if DEBUG
        let entitlements = Bundle.main.infoDictionary
        // Check via environment — sandboxed apps have APP_SANDBOX_CONTAINER_ID
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil {
            Logger.shared.warning(
                "WARNING: App Sandbox is enabled. Accessibility APIs will not work. " +
                "Disable sandbox in entitlements."
            )
        }

        // Also check the entitlements file directly
        if let sandboxEnabled = entitlements?["com.apple.security.app-sandbox"] as? Bool,
           sandboxEnabled {
            Logger.shared.warning(
                "WARNING: App Sandbox entitlement is set to true. Accessibility APIs will not work."
            )
        }

        // Check for ad-hoc signing — warn that TCC entries won't persist across rebuilds
        var staticCode: SecStaticCode?
        if SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
           let staticCode {
            var info: CFDictionary?
            if SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: 0), &info) == errSecSuccess,
               let dict = info as? [String: Any],
               let flags = dict["flags"] as? UInt32,
               (flags & 0x2) != 0 { // kSecCodeSignatureAdhoc = 0x2
                Logger.shared.warning(
                    "WARNING: App is ad-hoc signed (no development team). " +
                    "Accessibility TCC entries will break on every rebuild. " +
                    "Set DEVELOPMENT_TEAM in Xcode project settings."
                )
            }
        }
        #endif
    }

    // MARK: - App Restart

    /// Save current state and restart the app to pick up permission changes.
    func restartApp(onboardingStep: Int? = nil, fromSettings: Bool = false) {
        // Save state for restoration after relaunch
        if let step = onboardingStep {
            defaults.set(step, forKey: AppConstants.UserDefaultsKeys.pendingRestartOnboardingStep)
        }
        if fromSettings {
            defaults.set(true, forKey: AppConstants.UserDefaultsKeys.pendingRestartFromSettings)
        }
        defaults.synchronize()

        // Launch a new instance
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.open(bundleURL)

        // Terminate current instance after a brief delay to allow the new one to launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }

    /// Check for and clear any pending restart state. Returns the onboarding step to resume, or nil.
    func consumePendingRestartOnboardingStep() -> Int? {
        let key = AppConstants.UserDefaultsKeys.pendingRestartOnboardingStep
        let step = defaults.object(forKey: key) as? Int
        if step != nil {
            defaults.removeObject(forKey: key)
        }
        return step
    }

    /// Check and clear pending settings navigation state.
    func consumePendingRestartFromSettings() -> Bool {
        let key = AppConstants.UserDefaultsKeys.pendingRestartFromSettings
        let value = defaults.bool(forKey: key)
        if value {
            defaults.removeObject(forKey: key)
        }
        return value
    }
}
