import SwiftUI

struct OnboardingView: View {
    @ObservedObject var mainViewModel: MainViewModel
    @StateObject private var settingsVM = SettingsViewModel()
    @ObservedObject private var configService = ConfigurationService.shared
    @ObservedObject private var onboardingManager = OnboardingManager.shared

    @State private var currentStep = 0
    @State private var slideDirection: Edge = .trailing
    @State private var demoCompleted = false
    @State private var demoStarted = false
    @ObservedObject private var accessibilityService = AccessibilityService.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isWindowMode) private var isWindowMode

    @State private var selectedOnboardingMode: AppMode = .menubarOnly

    private let totalSteps = 6

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            ZStack {
                switch currentStep {
                case 0: welcomeStep.transition(stepTransition)
                case 1: apiKeyStep.transition(stepTransition)
                case 2: privacyStep.transition(stepTransition)
                case 3: accessibilityStep.transition(stepTransition)
                case 4: demoStep.transition(stepTransition)
                case 5: workflowChoiceStep.transition(stepTransition)
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.15)
                    : .spring(response: 0.4, dampingFraction: 0.85),
                value: currentStep
            )

            // Progress dots
            progressDots
                .padding(.bottom, 16)
        }
        .frame(
            minWidth: isWindowMode ? nil : 420,
            maxWidth: isWindowMode ? .infinity : 420,
            minHeight: isWindowMode ? nil : 580,
            maxHeight: isWindowMode ? .infinity : 580
        )
        .onAppear {
            let provider = configService.configuration.selectedProvider
            settingsVM.loadAPIKey(for: provider)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.promptcraft.restoreOnboardingStep"))) { notification in
            if let step = notification.userInfo?["step"] as? Int {
                currentStep = step
            }
        }
    }

    // MARK: - Step Transition

    private var stepTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: slideDirection).combined(with: .opacity),
            removal: .move(edge: slideDirection == .trailing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == currentStep ? 8 : 6, height: index == currentStep ? 8 : 6)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                        value: currentStep
                    )
            }
        }
    }

    // MARK: - Navigation

    private func goToNext() {
        slideDirection = .trailing
        withAnimation {
            currentStep = min(currentStep + 1, totalSteps - 1)
        }
    }

    private func goToPrevious() {
        slideDirection = .leading
        withAnimation {
            currentStep = max(currentStep - 1, 0)
        }
    }

    private func finishOnboarding() {
        onboardingManager.completeOnboarding()
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.bottom, 20)

            Text("Welcome to PromptCraft")
                .font(.system(size: 24, weight: .bold))
                .padding(.bottom, 8)

            Text("Transform messy thoughts into powerful AI prompts.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)

            Text("PromptCraft lives in your menu bar and turns rough ideas into structured, effective prompts in seconds. Just type, pick a style, and let AI do the polishing.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            Spacer()

            Button(action: goToNext) {
                Text("Get Started")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(TactileButtonStyle())
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 2: API Key Setup

    private var apiKeyStep: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 28)

                Text("Connect Your AI")
                    .font(.system(size: 22, weight: .bold))

                Text("Choose a provider and enter your API key.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 20)

            // Provider selector
            Picker("", selection: Binding(
                get: { configService.configuration.selectedProvider },
                set: { newProvider in
                    configService.update { $0.selectedProvider = newProvider }
                    settingsVM.loadAPIKey(for: newProvider)
                    settingsVM.validationState = .idle
                    configService.update { $0.selectedModelName = newProvider.defaultModelName }
                }
            )) {
                Text("Claude").tag(LLMProvider.anthropicClaude)
                Text("OpenAI").tag(LLMProvider.openAI)
                Text("OpenRouter").tag(LLMProvider.openRouter)
                Text("Ollama").tag(LLMProvider.ollama)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 40)
            .padding(.bottom, 16)

            // API key input or provider-specific view
            if LicensingService.shared.licenseType == .cloud {
                cloudOnboardingView
                    .padding(.horizontal, 40)
            } else if configService.configuration.selectedProvider == .ollama {
                ollamaOnboardingView
                    .padding(.horizontal, 40)
            } else if configService.configuration.selectedProvider == .openRouter {
                openRouterOnboardingView
                    .padding(.horizontal, 40)
            } else {
                apiKeyOnboardingView
                    .padding(.horizontal, 40)
            }

            Spacer()

            // Navigation buttons
            HStack(spacing: 12) {
                Button(action: goToPrevious) {
                    Text("Back")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: goToNext) {
                    Text("Skip for Now")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: goToNext) {
                    Text("Next")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(nextButtonEnabled ? Color.accentColor : Color.secondary.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(TactileButtonStyle())
                .disabled(!nextButtonEnabled)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }

    private var nextButtonEnabled: Bool {
        if configService.configuration.selectedProvider == .ollama {
            return settingsVM.validationState == .valid
        }
        return settingsVM.validationState == .valid
    }

    private var apiKeyOnboardingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Group {
                    if settingsVM.isKeyVisible {
                        TextField("Enter API key...", text: $settingsVM.apiKeyText)
                    } else {
                        SecureField("Enter API key...", text: $settingsVM.apiKeyText)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit {
                    settingsVM.saveAPIKey(for: configService.configuration.selectedProvider)
                }

                Button(action: { settingsVM.isKeyVisible.toggle() }) {
                    Image(systemName: settingsVM.isKeyVisible ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            // Validate button
            HStack(spacing: 8) {
                Button(action: {
                    settingsVM.saveAPIKey(for: configService.configuration.selectedProvider)
                    settingsVM.validateAPIKey(for: configService.configuration.selectedProvider)
                }) {
                    HStack(spacing: 6) {
                        if settingsVM.validationState == .validating {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                        }
                        Text("Validate")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(settingsVM.apiKeyText.isEmpty || settingsVM.validationState == .validating)

                if case .valid = settingsVM.validationState {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Connected")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }

            if case .invalid(let message) = settingsVM.validationState {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            // Helper link
            if let url = settingsVM.apiKeyHelperURL {
                Link(settingsVM.apiKeyHelperText, destination: url)
                    .font(.system(size: 11))
            }
        }
    }

    private var cloudOnboardingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("No API key needed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.green)
            }

            Text("Your PromptCraft Cloud subscription includes built-in AI.\nNo API key setup required.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var ollamaOnboardingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(ollamaStatusColor)
                    .frame(width: 8, height: 8)
                Text(ollamaStatusText)
                    .font(.system(size: 13))

                Spacer()

                Button("Test Connection") {
                    settingsVM.testOllamaConnection()
                }
                .font(.system(size: 12))
                .controlSize(.small)
                .disabled(settingsVM.validationState == .validating)
            }

            if case .invalid(let message) = settingsVM.validationState {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            Text("Ollama runs locally -- no API key required.\nMake sure Ollama is running on your machine.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - OpenRouter onboarding view

    private var openRouterOnboardingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // API key field
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack {
                    if settingsVM.isKeyVisible {
                        TextField("sk-or-v1-...", text: $settingsVM.apiKeyText)
                            .font(.system(size: 13, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-or-v1-...", text: $settingsVM.apiKeyText)
                            .font(.system(size: 13, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(action: {
                        settingsVM.saveAPIKey(for: .openRouter)
                        settingsVM.validateAPIKey(for: .openRouter)
                        settingsVM.loadModels(for: .openRouter)
                    }) {
                        if case .validating = settingsVM.validationState {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Verify")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .controlSize(.small)
                    .disabled(settingsVM.apiKeyText.isEmpty || settingsVM.validationState == .validating)
                }
            }

            // Validation feedback
            if case .valid = settingsVM.validationState {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("API key verified").foregroundStyle(.green)
                }
                .font(.system(size: 11))
            } else if case .invalid(let msg) = settingsVM.validationState {
                Text(msg).font(.system(size: 11)).foregroundStyle(.red)
            }

            // Model picker (loads after key verified or from proxy)
            if settingsVM.isLoadingModels {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading models...").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else if !settingsVM.availableModels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { configService.configuration.selectedModelName },
                        set: { newVal in configService.update { $0.selectedModelName = newVal } }
                    )) {
                        ForEach(settingsVM.availableModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            // Helper text
            Text("200+ models including DeepSeek, Llama, Grok, Gemini and more.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button(action: {
                NSWorkspace.shared.open(URL(string: "https://openrouter.ai/settings/keys")!)
            }) {
                Text("Get free API key at openrouter.ai")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            settingsVM.loadModels(for: .openRouter)
        }
    }

    private var ollamaStatusColor: Color {
        switch settingsVM.validationState {
        case .valid: return .green
        case .invalid: return .red
        case .validating: return .orange
        case .idle: return Color.secondary
        }
    }

    private var ollamaStatusText: String {
        switch settingsVM.validationState {
        case .valid: return "Connected"
        case .invalid: return "Not connected"
        case .validating: return "Testing..."
        case .idle: return "Not tested"
        }
    }

    // MARK: - Step 3: Privacy

    @State private var showPrivacyDetail = false

    private var privacyStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.green, Color.green.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.bottom, 16)

            Text("Your Data Stays on Your Mac")
                .font(.system(size: 22, weight: .bold))
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 12) {
                privacyRow(
                    icon: "shield.checkered",
                    text: "All history and context stored locally, never uploaded"
                )
                privacyRow(
                    icon: "key.fill",
                    text: "API keys encrypted in macOS Keychain"
                )
                privacyRow(
                    icon: "arrow.right.arrow.left.circle",
                    text: "Prompts sent directly to your AI provider. We never see them"
                )
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 16)

            // Data flow diagram
            VStack(spacing: 6) {
                dataFlowDiagram(isCloud: false)

                if LicensingService.shared.licenseType == .cloud {
                    dataFlowDiagram(isCloud: true)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 12)

            Button(action: { showPrivacyDetail = true }) {
                Text("Learn More")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            Spacer()

            // Navigation
            HStack(spacing: 12) {
                Button(action: goToPrevious) {
                    Text("Back")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: goToNext) {
                    Text("Continue")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(TactileButtonStyle())
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showPrivacyDetail) {
            privacyDetailSheet
        }
    }

    private func privacyRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.green)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dataFlowDiagram(isCloud: Bool) -> some View {
        HStack(spacing: 8) {
            flowBox("Your Mac", icon: "laptopcomputer")

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if isCloud {
                flowBox("PromptCraft Proxy", icon: "cloud", subtitle: "no storage")

                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            flowBox("AI Provider", icon: "brain")
        }
    }

    private func flowBox(_ label: String, icon: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(label)
                .font(.system(size: 10, weight: .medium))
            if let sub = subtitle {
                Text("(\(sub))")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private var privacyDetailSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Privacy Details")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: { showPrivacyDetail = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    privacyDetailSection(
                        title: "Local Storage",
                        body: "All your prompt history, context engine data, styles, and preferences are stored locally on your Mac in Application Support and the macOS Keychain. Nothing is uploaded to PromptCraft servers."
                    )
                    privacyDetailSection(
                        title: "API Communication",
                        body: "When you optimize a prompt, it's sent directly from your Mac to the AI provider you've configured (Anthropic, OpenAI, or Ollama). PromptCraft acts only as a client. We never proxy, store, or analyze your prompts."
                    )
                    privacyDetailSection(
                        title: "PromptCraft Cloud",
                        body: "If you use PromptCraft Cloud, prompts are routed through our proxy server for authentication. The proxy forwards requests immediately and does not store or log prompt contents."
                    )
                    privacyDetailSection(
                        title: "License Validation",
                        body: "License keys are validated via Keygen.sh's API. Only your license key and machine identifier are sent. No prompt data is included."
                    )
                }
                .padding()
            }
        }
        .frame(width: 380, height: 400)
    }

    private func privacyDetailSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Step 4: Accessibility Permission (was Step 3)

    private var accessibilityStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 16)

            Text("Enable Global Shortcut")
                .font(.system(size: 22, weight: .bold))
                .padding(.bottom, 8)

            Text("PromptCraft can be activated from any app\nwith a keyboard shortcut.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)

            // Shortcut display
            shortcutDisplay
                .padding(.bottom, 20)

            Text("This requires accessibility access so PromptCraft\ncan listen for the shortcut globally.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            // Multi-state permission indicator
            accessibilityPermissionIndicator
                .padding(.horizontal, 40)

            // Xcode debug mode note
            if accessibilityService.isXcodeDebugMode && accessibilityService.permissionState != .granted {
                xcodeDebugNote
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }

            Text("You can always change this in System Settings later.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 12)

            Spacer()

            // Navigation
            HStack(spacing: 12) {
                Button(action: goToPrevious) {
                    Text("Back")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if accessibilityService.permissionState != .granted {
                    Button(action: goToNext) {
                        Text("Skip for Now")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: goToNext) {
                    Text("Next")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(TactileButtonStyle())
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .onAppear {
            accessibilityService.recheckPermission()
        }
    }

    private var accessibilityPermissionIndicator: some View {
        VStack(spacing: 10) {
            switch accessibilityService.permissionState {
            case .granted:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Accessibility access granted. Global shortcut and inline overlay are active.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                        .multilineTextAlignment(.center)
                }
                .transition(.scale.combined(with: .opacity))

            case .checking:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                    Text("Checking for permission...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)

            case .needsRestart:
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("macOS sometimes requires restarting the app to apply permission changes.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: {
                        accessibilityService.restartApp(onboardingStep: currentStep)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                            Text("Restart PromptCraft")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)

            case .notGranted:
                VStack(spacing: 10) {
                    Button(action: {
                        accessibilityService.openAccessibilitySettings()
                        accessibilityService.startPollingForPermission()
                    }) {
                        Text("Grant Access")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(TactileButtonStyle())

                    Text("After granting, PromptCraft will detect the change automatically.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: accessibilityService.permissionState)
    }

    private var xcodeDebugNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 11))
                .foregroundStyle(.blue)
                .padding(.top, 2)
            Text("Running in Xcode debug mode. Accessibility applies to Xcode, not this app. For testing, grant Xcode accessibility access, or build and run the app directly.")
                .font(.system(size: 11))
                .foregroundStyle(.blue.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var shortcutDisplay: some View {
        HStack(spacing: 6) {
            ForEach(shortcutKeys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            }
        }
    }

    private var shortcutKeys: [String] {
        let shortcut = configService.configuration.globalShortcut
        var keys: [String] = []
        if shortcut.commandModifier { keys.append("\u{2318}") }
        if shortcut.shiftModifier { keys.append("\u{21E7}") }
        if shortcut.optionModifier { keys.append("\u{2325}") }
        if shortcut.controlModifier { keys.append("\u{2303}") }
        keys.append(shortcut.keyEquivalent.uppercased())
        return keys
    }

    // MARK: - Step 5: Quick Demo (was Step 4)

    private var demoStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 20)

                Text("See It in Action")
                    .font(.system(size: 22, weight: .bold))

                Text("Watch PromptCraft transform a messy thought.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)

            // Sample input
            VStack(alignment: .leading, spacing: 4) {
                Text("Input")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(samplePrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 60)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            // Style badge
            HStack(spacing: 4) {
                Image(systemName: "hammer")
                    .font(.system(size: 10))
                Text("Engineering Directive")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
            .padding(.bottom, 8)

            if !demoStarted {
                Button(action: startDemo) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("Try it!")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(TactileButtonStyle())
                .disabled(onboardingManager.needsAPIKeyReminder)
                .padding(.bottom, 4)

                if onboardingManager.needsAPIKeyReminder {
                    Text("Set up an API key first to try the demo.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                // Output area
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Output")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if mainViewModel.isProcessing {
                            ThreeDotsLoading()
                        }
                    }

                    ScrollView {
                        HStack(alignment: .lastTextBaseline, spacing: 0) {
                            Text(mainViewModel.outputText)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)

                            if mainViewModel.isProcessing {
                                BlinkingCursorView(isStreaming: true)
                                    .padding(.trailing, 4)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
                .padding(.horizontal, 24)
            }

            if demoCompleted {
                Text("That messy thought just became a precise\nengineering prompt. Every time. In seconds.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .transition(.opacity)
            }

            Spacer(minLength: 8)

            // Navigation
            HStack(spacing: 12) {
                Button(action: goToPrevious) {
                    Text("Back")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if !demoStarted {
                    Button(action: goToNext) {
                        Text("Skip Demo")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: goToNext) {
                    Text(demoCompleted ? "Next" : (demoStarted ? "Next" : "Next"))
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(TactileButtonStyle())
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .onChange(of: mainViewModel.isProcessing) { processing in
            if !processing && demoStarted && !mainViewModel.outputText.isEmpty {
                withAnimation(.easeIn(duration: 0.3)) {
                    demoCompleted = true
                }
            }
        }
    }

    private let samplePrompt = "can you help me make a function that takes a list of users and filters out the ones who haven't logged in for more than 30 days i think it should return their emails too also make it fast"

    private func startDemo() {
        // Set up the main view model with the demo data
        mainViewModel.inputText = samplePrompt

        // Select Engineering Directive style
        let engineeringID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        if let style = mainViewModel.availableStyles.first(where: { $0.id == engineeringID }) {
            mainViewModel.selectStyle(style)
        }

        demoStarted = true

        // Start optimization after a short delay for visual effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            mainViewModel.optimizePrompt()
        }
    }

    // MARK: - Step 6: Choose Your Workflow

    private var workflowChoiceStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.bottom, 16)

            Text("Choose Your Workflow")
                .font(.system(size: 22, weight: .bold))
                .padding(.bottom, 8)

            Text("How would you like to use PromptCraft?")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)

            HStack(spacing: 16) {
                workflowCard(
                    mode: .menubarOnly,
                    icon: "menubar.rectangle",
                    title: "Menubar",
                    description: "Quick access from the menu bar. Perfect for fast, in-context optimization."
                )

                workflowCard(
                    mode: .desktopWindow,
                    icon: "macwindow",
                    title: "Desktop App",
                    description: "A full window for longer sessions. Resizable and always accessible."
                )
            }
            .padding(.horizontal, 32)

            Text("You can always change this in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 16)

            Spacer()

            // Navigation
            HStack(spacing: 12) {
                Button(action: goToPrevious) {
                    Text("Back")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    ConfigurationService.shared.update { $0.appMode = selectedOnboardingMode }
                    finishOnboarding()
                }) {
                    Text("Start Using PromptCraft")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(TactileButtonStyle())
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }

    private func workflowCard(mode: AppMode, icon: String, title: String, description: String) -> some View {
        let isSelected = selectedOnboardingMode == mode
        return Button(action: { selectedOnboardingMode = mode }) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
