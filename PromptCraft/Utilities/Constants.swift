import AppKit
import Carbon.HIToolbox

enum AppConstants {
    static let appName = "PromptCraft"
    static let bundleIdentifier = "com.promptcraft.app"

    /// Default global keyboard shortcut: Command+Shift+P
    enum DefaultShortcut {
        static let keyEquivalent = "p"
        static let modifiers: NSEvent.ModifierFlags = [.command, .shift]
        /// Virtual key code for 'P' key (Carbon kVK_ANSI_P)
        static let keyCode: UInt16 = UInt16(kVK_ANSI_P)
    }

    /// Keys for UserDefaults storage
    enum UserDefaultsKeys {
        static let appConfiguration = "com.promptcraft.appConfiguration"
        static let hasLaunchedBefore = "com.promptcraft.hasLaunchedBefore"
        static let accessibilityDialogShown = "com.promptcraft.accessibilityDialogShown"

        // Onboarding
        static let hasCompletedOnboarding = "com.promptcraft.hasCompletedOnboarding"

        // Contextual hints (each shown once)
        static let hintShownInputArea = "com.promptcraft.hintShownInputArea"
        static let hintShownStyleSelector = "com.promptcraft.hintShownStyleSelector"
        static let hintShownCopyButton = "com.promptcraft.hintShownCopyButton"
        static let hintShownShortcutUsed = "com.promptcraft.hintShownShortcutUsed"

        // Optimization counter for empty state guidance
        static let optimizationCount = "com.promptcraft.optimizationCount"

        // Notification permission
        static let notificationPermissionRequested = "com.promptcraft.notificationPermissionRequested"

        // Accessibility restart state
        static let pendingRestartOnboardingStep = "com.promptcraft.pendingRestartOnboardingStep"
        static let pendingRestartFromSettings = "com.promptcraft.pendingRestartFromSettings"

        // Trial & Licensing
        static let trialCachePolicy = "com.promptcraft.cachePolicy"
        static let trialNudgeDismissedDate = "com.promptcraft.trialNudgeDismissedDate"
        static let licenseLastValidated = "com.promptcraft.licenseLastValidated"
        static let licenseCachedResult = "com.promptcraft.licenseCachedResult"
        static let machineID = "com.promptcraft.machineID"
        static let offlineGraceStart = "com.promptcraft.offlineGraceStart"

        // Watch Folder
        static let watchFolderProcessedFiles = "com.promptcraft.watchFolderProcessedFiles"
    }

    /// Clipboard limits
    enum Clipboard {
        static let maxInputCharacters = 10_000
    }

    /// Custom Notification.Name values for inter-component communication
    enum Notifications {
        static let promptOptimized = Notification.Name("com.promptcraft.promptOptimized")
        static let styleChanged = Notification.Name("com.promptcraft.styleChanged")
        static let configurationChanged = Notification.Name("com.promptcraft.configurationChanged")
        static let shortcutActivated = Notification.Name("com.promptcraft.shortcutActivated")
        static let closePopover = Notification.Name("com.promptcraft.closePopover")
        static let lockPopover = Notification.Name("com.promptcraft.lockPopover")
        static let openPopoverWithText = Notification.Name("com.promptcraft.openPopoverWithText")
        static let navigateToSettings = Notification.Name("com.promptcraft.navigateToSettings")
        static let trialStateChanged = Notification.Name("com.promptcraft.trialStateChanged")
        static let licenseStateChanged = Notification.Name("com.promptcraft.licenseStateChanged")
        static let navigateToUpgrade = Notification.Name("com.promptcraft.navigateToUpgrade")
        static let accessibilityStateChanged = Notification.Name("com.promptcraft.accessibilityStateChanged")
        static let deepLinkActivation = Notification.Name("com.promptcraft.deepLinkActivation")
        static let openDesktopWindow = Notification.Name("com.promptcraft.openDesktopWindow")
        static let appModeChanged = Notification.Name("com.promptcraft.appModeChanged")
        static let resetAllSettings = Notification.Name("com.promptcraft.resetAllSettings")
    }

    /// PromptCraft Cloud API endpoints
    enum CloudAPI {
        private static let proxyBase = "https://promptcraft-cloud-proxy.ozzydev.workers.dev"
        static let baseURL = "\(proxyBase)/v1/optimize"
        static let ollamaModelsURL = "\(proxyBase)/v1/ollama-models"
        static let claudeModelsURL = "\(proxyBase)/v1/claude-models"
        static let openaiModelsURL = "\(proxyBase)/v1/openai-models"
        static let openRouterModelsURL = "\(proxyBase)/v1/openrouter-models"
        static let proCheckoutURL = "https://buy.stripe.com/PRICE_PRO_LINK"
        static let cloudMonthlyCheckoutURL = "https://buy.stripe.com/PRICE_CLOUD_MONTHLY_LINK"
        static let cloudAnnualCheckoutURL = "https://buy.stripe.com/PRICE_CLOUD_ANNUAL_LINK"
        static let customerPortalURL = "https://billing.stripe.com/p/login/PORTAL_LINK"
        static let restorePurchaseURL = "https://promptcraft.app/restore"
    }

    /// License validation API endpoints (Keygen.sh)
    enum KeygenAPI {
        static let accountID = "YOUR_KEYGEN_ACCOUNT_ID"
        static let productToken = "YOUR_KEYGEN_PRODUCT_TOKEN"
        static let baseURL = "https://api.keygen.sh/v1/accounts/\(accountID)"
        static let validateURL = "\(baseURL)/licenses/actions/validate"
        static let machinesURL = "\(baseURL)/machines"
    }
}
