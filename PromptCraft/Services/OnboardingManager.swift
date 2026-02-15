import Foundation
import Combine

final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    private let defaults = UserDefaults.standard

    @Published var shouldShowOnboarding: Bool
    @Published var optimizationCount: Int

    private init() {
        self.shouldShowOnboarding = !UserDefaults.standard.bool(
            forKey: AppConstants.UserDefaultsKeys.hasCompletedOnboarding
        )
        self.optimizationCount = UserDefaults.standard.integer(
            forKey: AppConstants.UserDefaultsKeys.optimizationCount
        )
    }

    // MARK: - Onboarding Flow

    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: AppConstants.UserDefaultsKeys.hasCompletedOnboarding)
    }

    func completeOnboarding() {
        defaults.set(true, forKey: AppConstants.UserDefaultsKeys.hasCompletedOnboarding)
        shouldShowOnboarding = false

        // Start the 14-day trial when onboarding completes
        if TrialService.shared.trialStartDate == nil {
            TrialService.shared.startTrial()
        }
    }

    func resetOnboarding() {
        defaults.set(false, forKey: AppConstants.UserDefaultsKeys.hasCompletedOnboarding)
        shouldShowOnboarding = true
    }

    // MARK: - Contextual Hints

    func hasShownHint(_ key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    func markHintShown(_ key: String) {
        defaults.set(true, forKey: key)
    }

    var shouldShowInputHint: Bool {
        hasCompletedOnboarding && !hasShownHint(AppConstants.UserDefaultsKeys.hintShownInputArea)
    }

    var shouldShowStyleHint: Bool {
        hasCompletedOnboarding && !hasShownHint(AppConstants.UserDefaultsKeys.hintShownStyleSelector)
    }

    var shouldShowCopyHint: Bool {
        hasCompletedOnboarding && !hasShownHint(AppConstants.UserDefaultsKeys.hintShownCopyButton)
    }

    var shouldShowShortcutCelebration: Bool {
        hasCompletedOnboarding && !hasShownHint(AppConstants.UserDefaultsKeys.hintShownShortcutUsed)
    }

    func dismissInputHint() {
        markHintShown(AppConstants.UserDefaultsKeys.hintShownInputArea)
    }

    func dismissStyleHint() {
        markHintShown(AppConstants.UserDefaultsKeys.hintShownStyleSelector)
    }

    func dismissCopyHint() {
        markHintShown(AppConstants.UserDefaultsKeys.hintShownCopyButton)
    }

    func dismissShortcutCelebration() {
        markHintShown(AppConstants.UserDefaultsKeys.hintShownShortcutUsed)
    }

    // MARK: - Optimization Counter

    /// Whether to show empty state guidance (sample prompts).
    var shouldShowEmptyStateGuidance: Bool {
        hasCompletedOnboarding && optimizationCount < 3
    }

    func incrementOptimizationCount() {
        optimizationCount += 1
        defaults.set(optimizationCount, forKey: AppConstants.UserDefaultsKeys.optimizationCount)
    }

    // MARK: - API Key Reminder

    /// Whether the user has any API key configured for the active provider.
    var needsAPIKeyReminder: Bool {
        let config = ConfigurationService.shared.configuration
        if config.selectedProvider == .ollama { return false }
        if config.selectedProvider == .promptCraftCloud { return false }
        return !KeychainService.shared.hasAPIKey(for: config.selectedProvider)
    }
}
