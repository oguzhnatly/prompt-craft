import Sparkle
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case aiProviders = "AI Providers"
    case extensions = "Extensions"
    case behavior = "Behavior"
    case contextEngine = "Context Engine"
    case privacyAbout = "Privacy & About"
}

struct SettingsView: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: SettingsViewModel
    var onManageStyles: () -> Void = {}
    var onManageTemplates: () -> Void = {}
    var updater: SPUUpdater?
    @ObservedObject private var configService = ConfigurationService.shared
    @ObservedObject private var contextEngine = ContextEngineService.shared
    @ObservedObject private var licensingService = LicensingService.shared
    @ObservedObject private var trialService = TrialService.shared
    @ObservedObject private var accessibilityService = AccessibilityService.shared

    @State private var selectedTab: SettingsTab = .general
    @State private var showAllDetectedProjects = false
    @State private var editingClusterID: UUID?
    @State private var pendingClusterName: String = ""
    @Namespace private var segmentedAnimation
    @ObservedObject private var styleService = StyleService.shared
    @ObservedObject private var watchFolderService = WatchFolderService.shared
    @ObservedObject private var localAPIService = LocalAPIService.shared
    @State private var localAPITokenCopied: Bool = false

    private var config: AppConfiguration { configService.configuration }

    private func configBinding<T>(_ keyPath: WritableKeyPath<AppConfiguration, T>) -> Binding<T> {
        Binding(
            get: { self.configService.configuration[keyPath: keyPath] },
            set: { newValue in self.configService.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private var selectableProviders: [LLMProvider] {
        var providers: [LLMProvider] = [.anthropicClaude, .openAI, .openRouter, .ollama]
        if licensingService.licenseType == .cloud {
            providers.append(.promptCraftCloud)
        }
        return providers
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            Divider()
            settingsTabBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    tabContent
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Tab Bar

    private var settingsTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }) {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedTab == tab
                                    ? Color.accentColor
                                    : Color(nsColor: .controlBackgroundColor)
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        selectedTab == tab
                                            ? Color.clear
                                            : Color(nsColor: .separatorColor),
                                        lineWidth: 0.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            generalAppModeSection
            sectionDivider
            generalAppearanceSection
            sectionDivider
            startupSection
            sectionDivider
            updatesSection
        case .aiProviders:
            providerSection
        case .behavior:
            optimizationSection
            sectionDivider
            clipboardSection
            sectionDivider
            keyboardShortcutSection
            sectionDivider
            inlineOverlaySection
            sectionDivider
            watchFolderSection
            sectionDivider
            localAPISection
        case .extensions:
            extensionsSection
                .padding(.top, 12)
        case .contextEngine:
            contextEngineSection
                .padding(.top, 12)
        case .privacyAbout:
            privacySection
                .padding(.top, 12)
            sectionDivider
            licenseSection
            sectionDivider
            aboutSection
            sectionDivider
            debugSection
        }
    }

    // MARK: - Header

    private var settingsHeader: some View {
        HStack(spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isPresented = false
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Settings")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .accessibilityLabel("Back to main view")
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: - Helpers

    private var sectionDivider: some View {
        Divider().padding(.vertical, 12)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
            .padding(.bottom, 8)
    }

    private var displayableClusters: [ProjectCluster] {
        contextEngine.displayableClusters
            .filter { $0.entryCount > 0 }
    }

    private var visibleProjectPills: [ProjectCluster] {
        Array(displayableClusters.prefix(5))
    }

    private var hiddenProjectPillCount: Int {
        max(0, displayableClusters.count - visibleProjectPills.count)
    }

    private func projectDisplayName(_ cluster: ProjectCluster, maxLength: Int = 25) -> String {
        contextEngine.sanitizedClusterName(for: cluster, maxLength: maxLength)
    }

    private func beginClusterRename(_ cluster: ProjectCluster) {
        editingClusterID = cluster.id
        pendingClusterName = projectDisplayName(cluster)
    }

    private func cancelClusterRename() {
        editingClusterID = nil
        pendingClusterName = ""
    }

    private func saveClusterRename(_ clusterID: UUID) {
        let success = viewModel.renameContextProject(clusterID: clusterID, to: pendingClusterName)
        if success {
            cancelClusterRename()
        }
    }

    private func settingToggle(
        _ title: String,
        description: String? = nil,
        binding: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Toggle("", isOn: binding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            if let desc = description {
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func animatedSegmentedPicker<T: Hashable>(
        _ options: [T],
        selection: Binding<T>,
        label: @escaping (T) -> String,
        id pickerID: String
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selection.wrappedValue = option
                    }
                }) {
                    Text(label(option))
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(
                            Group {
                                if selection.wrappedValue == option {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color(nsColor: .controlAccentColor))
                                        .matchedGeometryEffect(id: pickerID, in: segmentedAnimation)
                                }
                            }
                        )
                        .contentShape(Rectangle())
                        .foregroundStyle(selection.wrappedValue == option ? .white : .primary)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
        }
        .padding(2)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - General: App Mode

    private var generalAppModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("App Mode")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("App Mode")
                        .font(.system(size: 13))
                    Spacer()
                    animatedSegmentedPicker(
                        AppMode.allCases,
                        selection: configBinding(\.appMode),
                        label: { $0.displayName },
                        id: "appMode"
                    )
                    .fixedSize()
                }

                Text(appModeDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if config.appMode != .menubarOnly {
                    settingToggle(
                        "Show in Dock",
                        description: "Display the PromptCraft icon in the macOS Dock.",
                        binding: configBinding(\.showDockIcon)
                    )
                }
            }
        }
        .padding(.top, 12)
    }

    // MARK: - General: Appearance

    private var generalAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Appearance")

            HStack {
                Text("Theme")
                    .font(.system(size: 13))
                Spacer()
                animatedSegmentedPicker(
                    ThemePreference.allCases,
                    selection: configBinding(\.themePreference),
                    label: { $0.rawValue.capitalized },
                    id: "theme"
                )
                .fixedSize()
            }

            settingToggle(
                "Show character count",
                binding: configBinding(\.showCharacterCount)
            )

            settingToggle(
                "Sound on completion",
                binding: configBinding(\.playSoundOnComplete)
            )
        }
    }

    // MARK: - General: Updates

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Updates")

            HStack(spacing: 6) {
                Text("PromptCraft")
                    .font(.system(size: 13, weight: .medium))
                Text("v\(appVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Button(action: {
                updater?.checkForUpdates()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                    Text("Check for Updates")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(updater == nil)
        }
    }

    // MARK: - Behavior: Optimization

    private var optimizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Optimization")

            // Styles management
            Button(action: onManageStyles) {
                HStack(spacing: 8) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manage Styles")
                            .font(.system(size: 13, weight: .medium))
                        Text("Create, edit, reorder, and import custom styles")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            // Templates management
            Button(action: onManageTemplates) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manage Templates")
                            .font(.system(size: 13, weight: .medium))
                        Text("Create, edit, and import prompt templates")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            Divider().padding(.vertical, 2)

            // Output verbosity
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Default output verbosity")
                        .font(.system(size: 13))
                    Spacer()
                    animatedSegmentedPicker(
                        OutputVerbosity.allCases,
                        selection: configBinding(\.outputVerbosity),
                        label: { $0.displayName },
                        id: "verbosity"
                    )
                    .fixedSize()
                }
                Text(config.outputVerbosity.descriptionText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            settingToggle(
                "Auto-copy result to clipboard",
                binding: configBinding(\.autoCopyToClipboard)
            )

            settingToggle(
                "Quick Optimize mode",
                description: "Automatically start optimization when opened via shortcut with clipboard text.",
                binding: configBinding(\.quickOptimizeEnabled)
            )

            if config.quickOptimizeEnabled {
                settingToggle(
                    "Auto-close after Quick Optimize",
                    description: "Automatically close the popover after Quick Optimize completes.",
                    binding: configBinding(\.quickOptimizeAutoClose)
                )
            }

            // Default export format
            HStack {
                Text("Default export format")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: configBinding(\.defaultExportFormat)) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            settingToggle(
                "Explain mode",
                description: "Show a pipeline breakdown after each optimization, revealing how RMPA processed your prompt.",
                binding: configBinding(\.explainModeEnabled)
            )
        }
        .padding(.top, 12)
    }

    // MARK: - Behavior: Clipboard

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Clipboard")

            settingToggle(
                "Auto-capture clipboard on shortcut",
                description: "Automatically paste clipboard contents into the input when triggered via keyboard shortcut.",
                binding: configBinding(\.clipboardCaptureEnabled)
            )

            settingToggle(
                "Auto-capture selected text",
                description: "Simulates \u{2318}C to capture currently selected text. Requires accessibility access.",
                binding: configBinding(\.autoCaptureSelectedText)
            )

            settingToggle(
                "Clipboard history (while PromptCraft is open)",
                description: "Remembers your last 20 copied texts while PromptCraft is open. Nothing is saved to disk.",
                binding: configBinding(\.clipboardHistoryEnabled)
            )
        }
    }

    // MARK: - About: Debug

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Debug")

            Button(action: {
                let logs = Logger.shared.recentLogs()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(logs, forType: .string)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11))
                    Text("Copy Logs")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy recent logs to clipboard for bug reporting")

            Button(action: {
                OnboardingManager.shared.resetOnboarding()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "hand.wave")
                        .font(.system(size: 11))
                    Text("Reset Onboarding")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button(action: { viewModel.showResetConfirmation = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                    Text("Reset All Settings")
                        .font(.system(size: 13))
                }
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .alert("Reset All Settings?", isPresented: $viewModel.showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { viewModel.resetAllSettings() }
            } message: {
                Text("This will reset all settings to their defaults, remove stored API keys, clear current output, and restart onboarding. This cannot be undone.")
            }
        }
    }

    // MARK: - LLM Provider Section

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("LLM Provider")

            animatedSegmentedPicker(
                selectableProviders,
                selection: configBinding(\.selectedProvider),
                label: { providerShortName($0) },
                id: "provider"
            )
            .onChange(of: config.selectedProvider) { newProvider in
                viewModel.loadAPIKey(for: newProvider)
                viewModel.loadModels(for: newProvider)
                viewModel.validationState = .idle
                configService.update { $0.selectedModelName = newProvider.defaultModelName }
            }

            if config.selectedProvider == .promptCraftCloud {
                cloudProviderNote
            } else if config.selectedProvider == .ollama {
                ollamaConnectionView
            } else {
                apiKeyView
            }

            modelSelectorView

            advancedLLMView
        }
        .padding(.top, 12)
    }

    private func providerShortName(_ provider: LLMProvider) -> String {
        switch provider {
        case .anthropicClaude: return "Claude"
        case .openAI: return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama"
        case .custom: return "Custom"
        case .promptCraftCloud: return "Cloud"
        }
    }

    // MARK: - Cloud Provider Note

    private var cloudProviderNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Included with your Cloud subscription")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            }
            Text("No API key needed. Requests are routed through PromptCraft Cloud.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - API Key

    private var apiKeyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API Key")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Group {
                    if viewModel.isKeyVisible {
                        TextField("Enter API key...", text: $viewModel.apiKeyText)
                    } else {
                        SecureField("Enter API key...", text: $viewModel.apiKeyText)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit {
                    viewModel.saveAPIKey(for: config.selectedProvider)
                }

                Button(action: { viewModel.isKeyVisible.toggle() }) {
                    Image(systemName: viewModel.isKeyVisible ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.saveAPIKey(for: config.selectedProvider)
                    viewModel.validateAPIKey(for: config.selectedProvider)
                }) {
                    validationIcon
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.validationState == .validating)
            }

            if case .invalid(let message) = viewModel.validationState {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            if viewModel.apiKeyText.isEmpty, let url = viewModel.apiKeyHelperURL {
                Link(viewModel.apiKeyHelperText, destination: url)
                    .font(.system(size: 11))
            }
        }
    }

    @ViewBuilder
    private var validationIcon: some View {
        switch viewModel.validationState {
        case .idle:
            Image(systemName: "checkmark.shield")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        case .validating:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        case .valid:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
        case .invalid:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Ollama Connection

    @State private var isInstallingOllama = false
    @State private var isAutoStartingOllama = false
    @State private var ollamaInstallStep: String?
    @State private var ollamaInstallError: String?
    @State private var showOllamaConfetti = false
    @State private var ollamaAutoStartAttempted = false
    @State private var showDeleteModelConfirmation = false
    @State private var modelToDelete: LLMModelInfo?

    private var ollamaConnectionView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connection")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(ollamaStatusColor)
                        .frame(width: 8, height: 8)
                    Text(ollamaStatusText)
                        .font(.system(size: 12))
                }

                Spacer()

                if showOllamaConfetti {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                        Text("Ready to use!")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button("Test Connection") {
                        ensureOllamaRunning()
                    }
                    .font(.system(size: 12))
                    .controlSize(.small)
                    .disabled(viewModel.validationState == .validating || isInstallingOllama || isAutoStartingOllama)
                }
            }

            // Show install UI only when not connected AND not busy AND no binary found
            if case .invalid = viewModel.validationState,
               !isInstallingOllama, !isAutoStartingOllama {
                if ollamaFindBinary() == nil {
                    // Ollama not installed at all
                    HStack(spacing: 10) {
                        Button(action: installOllama) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 11))
                                Text("Install Ollama")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            if let url = URL(string: "https://ollama.com/download/mac") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Text("Download manually")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // Ollama installed but server not running
                    HStack(spacing: 10) {
                        Button(action: { startOllamaServe() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "play.circle")
                                    .font(.system(size: 11))
                                Text("Start Ollama Server")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isInstallingOllama || isAutoStartingOllama {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(ollamaInstallStep ?? "Setting up Ollama...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            if let error = ollamaInstallError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            Text("Ollama runs locally. No API key required.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .overlay(alignment: .top) {
            if showOllamaConfetti {
                OllamaConfettiView()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showOllamaConfetti)
        .onAppear {
            if config.selectedProvider == .ollama && viewModel.validationState == .idle {
                ensureOllamaRunning()
            }
        }
    }

    // MARK: - Ollama: Ensure Running (auto-start if installed)

    /// Master function: test connection → if fails, try to start binary → poll → confetti or show install.
    private func ensureOllamaRunning() {
        ollamaInstallError = nil

        Task {
            // Step 1: Quick connection test
            let port = ConfigurationService.shared.configuration.ollamaPort
            if await ollamaIsReachable(port: port) {
                await MainActor.run {
                    viewModel.testOllamaConnection()
                }
                return
            }

            // Step 2: Not reachable — try to find and start binary
            if let binary = ollamaFindBinary() {
                await MainActor.run {
                    isAutoStartingOllama = true
                    ollamaInstallStep = "Starting Ollama server..."
                }

                ollamaLaunchServe(binaryPath: binary)

                // Step 3: Poll for server
                await MainActor.run {
                    ollamaInstallStep = "Waiting for Ollama to start..."
                }

                let connected = await ollamaPollUntilReady(port: port, attempts: 20)

                await MainActor.run {
                    isAutoStartingOllama = false
                    ollamaInstallStep = nil

                    if connected {
                        ollamaShowSuccess()
                    } else {
                        viewModel.testOllamaConnection()
                    }
                }
            } else {
                // Binary not found at all — just show the test result
                await MainActor.run {
                    viewModel.testOllamaConnection()
                }
            }
        }
    }

    // MARK: - Ollama: Start Server

    /// Attempts to start `ollama serve` in the background. Non-blocking.
    private func startOllamaServe() {
        guard let binary = ollamaFindBinary() else { return }
        ollamaInstallError = nil

        isAutoStartingOllama = true
        ollamaInstallStep = "Starting Ollama server..."

        Task {
            ollamaLaunchServe(binaryPath: binary)

            await MainActor.run {
                ollamaInstallStep = "Waiting for Ollama to start..."
            }

            let port = ConfigurationService.shared.configuration.ollamaPort
            let connected = await ollamaPollUntilReady(port: port, attempts: 20)

            await MainActor.run {
                isAutoStartingOllama = false
                ollamaInstallStep = nil

                if connected {
                    ollamaShowSuccess()
                } else {
                    ollamaInstallError = "Server started but not responding. Check if port \(port) is correct."
                    viewModel.testOllamaConnection()
                }
            }
        }
    }

    // MARK: - Ollama: Install (full pipeline with fallbacks)

    private func installOllama() {
        isInstallingOllama = true
        ollamaInstallError = nil
        ollamaInstallStep = "Installing Ollama..."

        Task.detached {
            let installed = await ollamaInstallPipeline()

            if !installed {
                await MainActor.run {
                    isInstallingOllama = false
                    ollamaInstallStep = nil
                }
                return
            }

            // Installed — now find binary and start serve
            await MainActor.run {
                ollamaInstallStep = "Starting Ollama server..."
            }

            // Give filesystem a moment to settle
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            if let binary = ollamaFindBinary() {
                ollamaLaunchServe(binaryPath: binary)
            }

            await MainActor.run {
                ollamaInstallStep = "Waiting for Ollama to start..."
            }

            let port = await ConfigurationService.shared.configuration.ollamaPort
            let connected = await ollamaPollUntilReady(port: port, attempts: 30)

            await MainActor.run {
                isInstallingOllama = false
                ollamaInstallStep = nil

                if connected {
                    ollamaShowSuccess()
                } else {
                    ollamaInstallError = "Installed successfully but server didn't respond. Try restarting the app or running `ollama serve` in Terminal."
                    viewModel.testOllamaConnection()
                }
            }
        }
    }

    /// Tries multiple install methods. Returns true if any succeeded.
    private func ollamaInstallPipeline() async -> Bool {
        // === Attempt 1: Homebrew ===
        let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for path in brewPaths {
            if FileManager.default.fileExists(atPath: path) {
                await MainActor.run { ollamaInstallStep = "Installing via Homebrew..." }
                if ollamaRunProcess(path, arguments: ["install", "ollama"]) {
                    return true
                }
            }
        }

        // === Attempt 2: Official install script via curl ===
        await MainActor.run { ollamaInstallStep = "Installing via official script..." }
        let curlPaths = ["/usr/bin/curl", "/opt/homebrew/bin/curl", "/usr/local/bin/curl"]
        for curlPath in curlPaths {
            if FileManager.default.fileExists(atPath: curlPath) {
                // curl -fsSL https://ollama.com/install.sh | sh
                let shellPaths = ["/bin/zsh", "/bin/bash", "/bin/sh"]
                for shell in shellPaths {
                    if FileManager.default.fileExists(atPath: shell) {
                        if ollamaRunProcess(shell, arguments: ["-c", "\(curlPath) -fsSL https://ollama.com/install.sh | \(shell)"]) {
                            return true
                        }
                        break
                    }
                }
                break
            }
        }

        // === Attempt 3: Download .dmg via curl, mount, and copy ===
        await MainActor.run { ollamaInstallStep = "Downloading Ollama app..." }
        for curlPath in curlPaths {
            if FileManager.default.fileExists(atPath: curlPath) {
                let dmgPath = "/tmp/Ollama.dmg"
                // Download the macOS app zip (more reliable than .dmg for automation)
                if ollamaRunProcess(curlPath, arguments: ["-fsSL", "-o", dmgPath, "https://ollama.com/download/Ollama-darwin.zip"]) {
                    await MainActor.run { ollamaInstallStep = "Extracting Ollama..." }
                    // Unzip to /Applications
                    if ollamaRunProcess("/usr/bin/ditto", arguments: ["-xk", dmgPath, "/Applications"]) {
                        // Clean up
                        try? FileManager.default.removeItem(atPath: dmgPath)
                        // The Ollama.app puts the binary at a different path — try to launch the app
                        let appPath = "/Applications/Ollama.app"
                        if FileManager.default.fileExists(atPath: appPath) {
                            let ws = NSWorkspace.shared
                            let appURL = URL(fileURLWithPath: appPath)
                            if #available(macOS 13.0, *) {
                                try? await ws.openApplication(at: appURL, configuration: .init())
                            } else {
                                ws.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
                            }
                            // Give the app time to register its CLI binary
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            return true
                        }
                    }
                    try? FileManager.default.removeItem(atPath: dmgPath)
                }
                break
            }
        }

        // === Attempt 4: Last resort — open browser ===
        await MainActor.run {
            ollamaInstallStep = nil
            ollamaInstallError = "Automatic install failed. Opening download page..."
            if let url = URL(string: "https://ollama.com/download/mac") {
                NSWorkspace.shared.open(url)
            }
        }
        return false
    }

    // MARK: - Ollama: Helpers

    /// Find the ollama binary across all known locations.
    private func ollamaFindBinary() -> String? {
        let paths = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/usr/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama",
            "\(NSHomeDirectory())/.ollama/bin/ollama",
            "\(NSHomeDirectory())/bin/ollama",
            "/Applications/Ollama.app/Contents/MacOS/ollama",
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Launch `ollama serve` as a background process. Non-blocking, non-fatal.
    private func ollamaLaunchServe(binaryPath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Set environment so it doesn't inherit sandbox restrictions
        var env = ProcessInfo.processInfo.environment
        env["OLLAMA_HOST"] = "127.0.0.1:\(ConfigurationService.shared.configuration.ollamaPort)"
        process.environment = env
        do {
            try process.run()
            // Don't waitUntilExit — it runs as a long-lived server
        } catch {
            // Non-fatal: server might already be running, or app bundle binary might need different launch
        }

        // Also try launching Ollama.app if it exists (handles the app-bundle case)
        let appPath = "/Applications/Ollama.app"
        if FileManager.default.fileExists(atPath: appPath) {
            let appURL = URL(fileURLWithPath: appPath)
            if #available(macOS 13.0, *) {
                Task {
                    try? await NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
                }
            } else {
                NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
            }
        }
    }

    /// Check if Ollama API is reachable right now.
    private func ollamaIsReachable(port: Int) async -> Bool {
        guard let url = URL(string: "http://localhost:\(port)/api/tags") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        if let (_, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse, http.statusCode == 200 {
            return true
        }
        return false
    }

    /// Poll Ollama until it responds, up to `attempts` times (0.5s apart).
    private func ollamaPollUntilReady(port: Int, attempts: Int) async -> Bool {
        for _ in 0..<attempts {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if await ollamaIsReachable(port: port) {
                return true
            }
        }
        return false
    }

    /// Run a process synchronously. Returns true if exit status == 0.
    private func ollamaRunProcess(_ path: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Celebrate successful Ollama connection.
    private func ollamaShowSuccess() {
        viewModel.testOllamaConnection()
        viewModel.loadModels(for: .ollama)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showOllamaConfetti = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation { showOllamaConfetti = false }
        }
    }

    private var ollamaStatusColor: Color {
        switch viewModel.validationState {
        case .valid: return .green
        case .invalid: return .red
        case .validating: return .orange
        case .idle: return Color.secondary
        }
    }

    private var ollamaStatusText: String {
        switch viewModel.validationState {
        case .valid: return "Connected"
        case .invalid: return "Not connected"
        case .validating: return "Testing..."
        case .idle: return "Not tested"
        }
    }

    // MARK: - Model Selector

    private var modelSelectorView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if viewModel.isLoadingModels {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading models...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.availableModels.isEmpty {
                Text("No models available")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if config.selectedProvider == .ollama || config.selectedProvider == .openRouter {
                ollamaModelSelector
            } else {
                Picker("", selection: configBinding(\.selectedModelName)) {
                    ForEach(viewModel.availableModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .labelsHidden()
            }
        }
    }

    // MARK: - Ollama Model Selector

    private var ollamaModelSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Download progress
            if let status = viewModel.modelDownloadStatus {
                HStack(spacing: 6) {
                    if viewModel.downloadingModelName != nil {
                        ProgressView().controlSize(.small)
                    }
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if viewModel.downloadingModelName != nil {
                        Button {
                            viewModel.cancelModelDownload()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel download")
                    }
                }
                if let progress = viewModel.modelDownloadProgress, progress > 0 {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
            }

            // Installed models section
            let installed = viewModel.availableModels.filter(\.isInstalled)
            if !installed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("INSTALLED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)

                    ForEach(installed) { model in
                        ollamaModelRow(model: model, isSelected: config.selectedModelName == model.id)
                            .onTapGesture {
                                configService.update { $0.selectedModelName = model.id }
                            }
                    }
                }
            }

            // Available to download section
            let notInstalled = viewModel.availableModels.filter { !$0.isInstalled }
            if !notInstalled.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(config.selectedProvider == .openRouter ? "AVAILABLE MODELS" : "AVAILABLE TO DOWNLOAD")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)
                        .padding(.top, 4)

                    ForEach(notInstalled) { model in
                        ollamaModelRow(model: model, isSelected: config.selectedModelName == model.id)
                            .onTapGesture {
                                if config.selectedProvider == .openRouter {
                                    configService.update { $0.selectedModelName = model.id }
                                } else {
                                    viewModel.pullOllamaModel(name: model.id)
                                }
                            }
                    }
                }
            }
        }
        .alert("Delete Model", isPresented: $showDeleteModelConfirmation) {
            Button("Cancel", role: .cancel) { modelToDelete = nil }
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    viewModel.deleteOllamaModel(name: model.id)
                    modelToDelete = nil
                }
            }
        } message: {
            if let model = modelToDelete {
                Text("Are you sure you want to delete \"\(model.displayName)\"? You can re-download it later.")
            }
        }
    }

    private func ollamaModelRow(model: LLMModelInfo, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            // Selection indicator or download icon
            if model.isInstalled || config.selectedProvider == .openRouter {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary.opacity(0.4))
            } else {
                if viewModel.downloadingModelName == model.id {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                }
            }

            // Model info
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(model.displayName)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle((model.isInstalled || config.selectedProvider == .openRouter) ? .primary : .secondary)

                    if let size = model.parameterSize {
                        Text(size)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(nsColor: .separatorColor).opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                if let bestFor = model.bestFor {
                    Text(bestFor)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Tags
            HStack(spacing: 3) {
                if model.isRecommended {
                    ollamaModelTag("Recommended", color: .green)
                }
                ForEach(Array(model.tags.prefix(2)), id: \.self) { tag in
                    ollamaModelTag(tag.capitalized, color: ollamaTagColor(for: tag))
                }
            }

            // Delete button for installed models (Ollama only)
            if model.isInstalled && config.selectedProvider != .openRouter {
                Button {
                    modelToDelete = model
                    showDeleteModelConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Delete model")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func ollamaModelTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func ollamaTagColor(for tag: String) -> Color {
        switch tag.lowercased() {
        case "thinking": return .purple
        case "tools": return .blue
        case "vision": return .orange
        case "fast": return .green
        default: return .secondary
        }
    }

    // MARK: - Advanced LLM Settings

    private var advancedLLMView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showAdvancedLLM.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.showAdvancedLLM ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                    Text("Advanced Settings")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if viewModel.showAdvancedLLM {
                VStack(alignment: .leading, spacing: 10) {
                    // Temperature
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Temperature")
                                .font(.system(size: 12))
                            Spacer()
                            Text(String(format: "%.1f", config.temperature))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: configBinding(\.temperature), in: 0...1, step: 0.1)
                            .controlSize(.small)
                        Text("Lower values produce more focused output; higher values increase creativity.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    // Max output tokens
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max Output Tokens")
                                .font(.system(size: 12))
                            Spacer()
                            Text("\(config.maxOutputTokens)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(config.maxOutputTokens) },
                                set: { newValue in configService.update { $0.maxOutputTokens = Int(newValue) } }
                            ),
                            in: 512...8192,
                            step: 256
                        )
                        .controlSize(.small)
                        Text("Maximum number of tokens in the optimized output.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    // Ollama Port (only when Ollama is selected)
                    if config.selectedProvider == .ollama {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Ollama Port")
                                    .font(.system(size: 12))
                                Spacer()
                                TextField("11434", text: Binding(
                                    get: { String(config.ollamaPort) },
                                    set: { newValue in
                                        if let port = Int(newValue), port > 0, port <= 65535 {
                                            configService.update { $0.ollamaPort = port }
                                        }
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                            }
                            Text("Default is 11434. Change if Ollama runs on a different port.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - License Section

    @State private var settingsLicenseKeyText: String = ""
    @State private var isActivatingLicense: Bool = false
    @State private var licenseActivationMessage: String?
    @State private var licenseActivationSuccess: Bool = false

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("License")

            if licensingService.isProUser {
                // Licensed state
                HStack(spacing: 8) {
                    Image(systemName: licensingService.licenseType == .cloud ? "cloud.fill" : "star.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(licensingService.licenseType == .cloud ? .blue : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(licensingService.licenseType == .cloud ? "Cloud License" : "Pro License")
                            .font(.system(size: 13, weight: .semibold))
                        if let email = licensingService.licenseEmail {
                            Text(email)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("Active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                }

                if let key = licensingService.licenseKey {
                    HStack {
                        Text("Key")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(maskedKey(key))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if let date = licensingService.activationDate {
                    HStack {
                        Text("Activated")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(date, style: .date)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Button(action: {
                        licensingService.deactivateLicense()
                    }) {
                        Text("Deactivate")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        if let url = URL(string: AppConstants.CloudAPI.customerPortalURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("Manage Subscription")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // Unlicensed state
                trialStatusRow

                VStack(alignment: .leading, spacing: 6) {
                    Text("License Key")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        SecureField("Enter license key...", text: $settingsLicenseKeyText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                        Button(action: activateSettingsLicense) {
                            if isActivatingLicense {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                            } else {
                                Text("Activate")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .disabled(settingsLicenseKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isActivatingLicense)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    if let msg = licenseActivationMessage {
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundStyle(licenseActivationSuccess ? .green : .red)
                    }
                }

                Button(action: {
                    if let url = URL(string: AppConstants.CloudAPI.proCheckoutURL) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "cart")
                            .font(.system(size: 11))
                        Text("Buy License")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var trialStatusRow: some View {
        HStack(spacing: 8) {
            if trialService.isExpired {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                Text("Trial expired")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            } else if case .active(let days) = trialService.trialState {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(days <= 4 ? .orange : .secondary)
                Text("Trial: \(days) day\(days == 1 ? "" : "s") remaining")
                    .font(.system(size: 12))
                    .foregroundStyle(days <= 4 ? .orange : .secondary)
            }
            Spacer()
        }
    }

    private func maskedKey(_ key: String) -> String {
        guard key.count > 6 else { return String(repeating: "\u{2022}", count: key.count) }
        let prefix = String(key.prefix(3))
        let suffix = String(key.suffix(3))
        let masked = String(repeating: "\u{2022}", count: min(8, key.count - 6))
        return prefix + masked + suffix
    }

    private func activateSettingsLicense() {
        let key = settingsLicenseKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isActivatingLicense = true
        licenseActivationMessage = nil

        Task {
            let success = await licensingService.activateLicense(key: key)
            await MainActor.run {
                isActivatingLicense = false
                licenseActivationSuccess = success
                if success {
                    licenseActivationMessage = "License activated!"
                    settingsLicenseKeyText = ""
                } else {
                    licenseActivationMessage = licensingService.validationError ?? "Invalid key."
                }
            }
        }
    }

    // MARK: - Styles Section

    private var stylesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Styles")

            Button(action: onManageStyles) {
                HStack(spacing: 8) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manage Styles")
                            .font(.system(size: 13, weight: .medium))
                        Text("Create, edit, reorder, and import custom styles")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Keyboard Shortcut Section

    private var keyboardShortcutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Keyboard Shortcut")

            ShortcutRecorderView(shortcut: configBinding(\.globalShortcut))

            // Feature status
            HStack(spacing: 6) {
                Circle()
                    .fill(accessibilityService.isAccessibilityGranted ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text("Global shortcut (\(config.globalShortcut.displayString)):")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(accessibilityService.isAccessibilityGranted ? "Active" : "Unavailable")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accessibilityService.isAccessibilityGranted ? .green : .red)
            }

            if !accessibilityService.isAccessibilityGranted {
                settingsAccessibilityActions
            }
        }
    }

    private var settingsAccessibilityActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text("Accessibility access required.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(action: {
                    accessibilityService.recheckPermission()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("Re-check")
                            .font(.system(size: 11))
                    }
                }
                .controlSize(.small)

                Button(action: {
                    accessibilityService.openAccessibilitySettings()
                    accessibilityService.startPollingForPermission()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "gear")
                            .font(.system(size: 10))
                        Text("Open System Settings")
                            .font(.system(size: 11))
                    }
                }
                .controlSize(.small)
            }

            if accessibilityService.permissionState == .checking {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                    Text("Checking...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if accessibilityService.permissionState == .needsRestart {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("Restart needed to apply changes.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Button("Restart") {
                        accessibilityService.restartApp(fromSettings: true)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .controlSize(.small)
                }
            }

            if accessibilityService.isXcodeDebugMode {
                Text("Xcode debug mode: accessibility applies to Xcode, not this app.")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue.opacity(0.8))
            }
        }
    }

    // MARK: - Behavior Section

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Behavior")

            settingToggle(
                "Auto-capture clipboard on shortcut",
                description: "Automatically paste clipboard contents into the input when triggered via keyboard shortcut.",
                binding: configBinding(\.clipboardCaptureEnabled)
            )

            settingToggle(
                "Auto-capture selected text",
                description: "Simulates \u{2318}C to capture currently selected text. Requires accessibility access.",
                binding: configBinding(\.autoCaptureSelectedText)
            )

            settingToggle(
                "Quick Optimize mode",
                description: "Automatically start optimization when opened via shortcut with clipboard text.",
                binding: configBinding(\.quickOptimizeEnabled)
            )

            settingToggle(
                "Auto-copy result to clipboard",
                binding: configBinding(\.autoCopyToClipboard)
            )

            if config.quickOptimizeEnabled {
                settingToggle(
                    "Auto-close after Quick Optimize",
                    description: "Automatically close the popover after Quick Optimize completes.",
                    binding: configBinding(\.quickOptimizeAutoClose)
                )
            }

        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Privacy")

            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                Text("Local & Private")
                    .font(.system(size: 13, weight: .medium))
            }
            Text("PromptCraft is completely local and private. Your prompts and data never leave your Mac. Everything is processed through your own API keys and stored on-device.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(action: { viewModel.exportConfiguration() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                        Text("Export All My Data")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.showClearHistoryConfirmation = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Delete All Data")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .alert("Delete All Data?", isPresented: $viewModel.showClearHistoryConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) { viewModel.clearHistory() }
                } message: {
                    Text("This will delete all \(viewModel.historyCount) history entries. This cannot be undone.")
                }
            }
        }
    }

    // MARK: - Templates Section

    @ObservedObject private var templateServiceRef = TemplateService.shared

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Templates")

            Text("\(templateServiceRef.templates.count) templates (\(templateServiceRef.templates.filter(\.isBuiltIn).count) built-in)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(action: { exportTemplates() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                        Text("Export Templates")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)

                Button(action: { importTemplates() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                        Text("Import Templates")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
            }

            // Default export format
            HStack {
                Text("Default export format")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: configBinding(\.defaultExportFormat)) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
        }
    }

    private func exportTemplates() {
        guard let data = TemplateService.shared.exportAsJSON() else { return }

        lockPopover(true)
        defer { lockPopover(false) }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PromptCraft-templates.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importTemplates() {
        lockPopover(true)
        defer { lockPopover(false) }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            _ = TemplateService.shared.importFromJSON(data)
        }
    }

    private func lockPopover(_ locked: Bool) {
        NotificationCenter.default.post(
            name: AppConstants.Notifications.lockPopover,
            object: nil,
            userInfo: ["locked": locked]
        )
    }

    // MARK: - Inline Overlay Section

    private var inlineOverlaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Inline Overlay")

            settingToggle(
                "Show inline overlay on text fields",
                description: "A floating pill appears near focused text fields in other apps for quick optimization.",
                binding: configBinding(\.inlineOverlayEnabled)
            )

            if config.inlineOverlayEnabled {
                // Delay picker
                HStack {
                    Text("Appearance delay")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: configBinding(\.inlineOverlayDelayMs)) {
                        Text("300ms").tag(300)
                        Text("500ms").tag(500)
                        Text("1000ms").tag(1000)
                        Text("2000ms").tag(2000)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }

                // Excluded apps
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Excluded apps")
                            .font(.system(size: 12))
                        Spacer()
                        Menu {
                            let apps = NSWorkspace.shared.runningApplications
                                .filter { $0.activationPolicy == .regular }
                                .compactMap { app -> (name: String, bundleID: String)? in
                                    guard let bundleID = app.bundleIdentifier,
                                          bundleID != Bundle.main.bundleIdentifier,
                                          !config.overlayExcludedApps.contains(bundleID) else { return nil }
                                    return (app.localizedName ?? bundleID, bundleID)
                                }
                                .sorted(by: { $0.name < $1.name })

                            if apps.isEmpty {
                                Text("No apps available")
                            } else {
                                ForEach(apps, id: \.bundleID) { app in
                                    Button(app.name) {
                                        configService.update { $0.overlayExcludedApps.append(app.bundleID) }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Add app to exclusion list")
                    }

                    if config.overlayExcludedApps.isEmpty {
                        Text("No excluded apps")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(config.overlayExcludedApps, id: \.self) { bundleID in
                            HStack(spacing: 6) {
                                Text(appNameForBundleID(bundleID))
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Spacer()
                                Button(action: {
                                    configService.update {
                                        $0.overlayExcludedApps.removeAll { $0 == bundleID }
                                    }
                                }) {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Inline overlay feature status
                HStack(spacing: 6) {
                    Circle()
                        .fill(accessibilityService.isAccessibilityGranted ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text("Inline overlay:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(accessibilityService.isAccessibilityGranted ? "Active" : "Unavailable")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accessibilityService.isAccessibilityGranted ? .green : .red)
                }

                if !accessibilityService.isAccessibilityGranted {
                    settingsAccessibilityActions
                }
            }
        }
    }

    private func appNameForBundleID(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = bundle.infoDictionary?["CFBundleName"] as? String {
            return name
        }
        return bundleID
    }

    // MARK: - Watch Folder Section

    private var watchFolderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Watch Folder")

            settingToggle(
                "Enable Watch Folder",
                description: "Monitor a folder for .txt files and auto-optimize them in the background.",
                binding: configBinding(\.watchFolderEnabled)
            )

            if config.watchFolderEnabled {
                // Folder path
                VStack(alignment: .leading, spacing: 6) {
                    Text("Watch path")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text(config.watchFolderPath)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )

                        Button(action: pickWatchFolder) {
                            Image(systemName: "folder")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help("Choose folder")

                        Button(action: revealWatchFolderInFinder) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                    }
                }

                // Style picker
                HStack {
                    Text("Optimization style")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: watchFolderStyleBinding) {
                        Text("Default (first enabled)").tag(nil as UUID?)
                        ForEach(styleService.getEnabled(), id: \.id) { style in
                            Text(style.displayName).tag(style.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }

                settingToggle(
                    "Auto-copy result to clipboard",
                    description: "Copy the optimized text to clipboard when processing completes.",
                    binding: configBinding(\.watchFolderAutoClipboard)
                )

                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(watchFolderService.isWatching ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text("Watch folder:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(watchFolderService.isWatching ? "Active" : "Inactive")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(watchFolderService.isWatching ? .green : .orange)
                }
            }
        }
    }

    private var watchFolderStyleBinding: Binding<UUID?> {
        Binding(
            get: { self.configService.configuration.watchFolderStyleID },
            set: { newValue in self.configService.update { $0.watchFolderStyleID = newValue } }
        )
    }

    // MARK: - Local API Section

    private var localAPISection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Local API Server")

            settingToggle(
                "Enable Local API",
                description: "Run a localhost HTTP server so external tools (Raycast, Alfred, curl) can optimize prompts.",
                binding: configBinding(\.localAPIEnabled)
            )

            if config.localAPIEnabled {
                // Port
                HStack {
                    Text("Port")
                        .font(.system(size: 13))
                    Spacer()
                    TextField("9847", value: configBinding(\.localAPIPort), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }

                // Token display + actions
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bearer token")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text(localAPIService.getOrCreateToken())
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(localAPIService.getOrCreateToken(), forType: .string)
                            localAPITokenCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                localAPITokenCopied = false
                            }
                        }) {
                            Image(systemName: localAPITokenCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help("Copy token")

                        Button(action: {
                            localAPIService.regenerateToken()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help("Regenerate token")
                    }
                }

                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(localAPIService.isRunning ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text("API server:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(localAPIService.isRunning ? "Active on port \(config.localAPIPort)" : "Inactive")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(localAPIService.isRunning ? .green : .orange)
                }
            }
        }
    }

    private func pickWatchFolder() {
        // Lock popover so it doesn't dismiss when the panel opens
        NotificationCenter.default.post(
            name: AppConstants.Notifications.lockPopover,
            object: nil,
            userInfo: ["locked": true]
        )

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose a folder to monitor for .txt files"

        panel.begin { [weak configService] response in
            defer {
                NotificationCenter.default.post(
                    name: AppConstants.Notifications.lockPopover,
                    object: nil,
                    userInfo: ["locked": false]
                )
            }
            if response == .OK, let url = panel.url {
                let path = url.path
                configService?.update { $0.watchFolderPath = path }
            }
        }
    }

    private func revealWatchFolderInFinder() {
        let expandedPath = (config.watchFolderPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath, isDirectory: true)

        // Create directory if it doesn't exist yet
        let fm = FileManager.default
        if !fm.fileExists(atPath: expandedPath) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }

        NSWorkspace.shared.open(url)
    }

    // MARK: - Context Engine Section

    private var contextEngineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Context Engine")

            settingToggle(
                "Enable Context Engine",
                description: "Learn from past optimizations to improve future ones. All data stays local.",
                binding: configBinding(\.contextEngineEnabled)
            )

            if config.contextEngineEnabled {
                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(contextEngine.isAvailable ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(contextEngine.isAvailable ? "Available" : "Not available (requires macOS 14+)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if contextEngine.isAvailable {
                    // Entry count
                    HStack {
                        Text("Stored entries")
                            .font(.system(size: 12))
                        Spacer()
                        Text("\(contextEngine.entryCount)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    // Detected projects
                    HStack {
                        Text("Detected projects")
                            .font(.system(size: 12))
                        Spacer()
                        Text("\(displayableClusters.count)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if !displayableClusters.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(visibleProjectPills) { cluster in
                                        projectPill(cluster)
                                    }

                                    if hiddenProjectPillCount > 0 && !showAllDetectedProjects {
                                        Button(action: {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                showAllDetectedProjects = true
                                            }
                                        }) {
                                            Text("+\(hiddenProjectPillCount) more")
                                                .font(.system(size: 11, weight: .medium))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(Color(nsColor: .controlBackgroundColor))
                                                .clipShape(Capsule())
                                                .overlay(
                                                    Capsule()
                                                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(showAllDetectedProjects ? displayableClusters : visibleProjectPills) { cluster in
                                    projectEditableRow(cluster)
                                }
                            }
                        }
                    } else {
                        Text("Projects appear after a cluster reaches at least 5 entries.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    // Average output efficiency
                    if let efficiency = contextEngine.averageOutputEfficiency {
                        HStack {
                            Text("Average output efficiency")
                                .font(.system(size: 12))
                            Spacer()
                            Text(String(format: "%.0f%%", efficiency * 100))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(efficiency <= 1.0 ? .green : .orange)
                        }
                    }

                    // Relevance threshold slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Relevance threshold")
                                .font(.system(size: 12))
                            Spacer()
                            Text(String(format: "%.2f", config.contextRelevanceThreshold))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(config.contextRelevanceThreshold) },
                                set: { newValue in configService.update { $0.contextRelevanceThreshold = Float(newValue) } }
                            ),
                            in: 0.3...0.95,
                            step: 0.05
                        )
                        .controlSize(.small)
                        Text("Higher values return fewer but more relevant results.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: { viewModel.reclusterContext() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11))
                                Text("Re-cluster")
                                    .font(.system(size: 12))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(contextEngine.entryCount < 3)

                        Button(action: { viewModel.showClearContextConfirmation = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                Text("Clear Context Data")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .disabled(contextEngine.entryCount == 0)
                    }
                    .alert("Clear Context Data?", isPresented: $viewModel.showClearContextConfirmation) {
                        Button("Cancel", role: .cancel) {}
                        Button("Clear", role: .destructive) { viewModel.clearContextData() }
                    } message: {
                        Text("This will delete all \(contextEngine.entryCount) context entries and detected projects. This cannot be undone.")
                    }
                }
            }
        }
    }

    private func projectPill(_ cluster: ProjectCluster) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: cluster.color))
                .frame(width: 6, height: 6)

            Text("\(projectDisplayName(cluster, maxLength: 20)) (\(cluster.entryCount))")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(hex: cluster.color).opacity(0.12))
        .foregroundStyle(Color(hex: cluster.color))
        .clipShape(Capsule())
    }

    private func projectEditableRow(_ cluster: ProjectCluster) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: cluster.color))
                .frame(width: 7, height: 7)

            if editingClusterID == cluster.id {
                TextField("Project name", text: $pendingClusterName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { saveClusterRename(cluster.id) }
                    .onExitCommand { cancelClusterRename() }
            } else {
                Text(projectDisplayName(cluster))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }

            Spacer()

            Text("\(cluster.entryCount)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(Capsule())

            if editingClusterID == cluster.id {
                Button(action: { saveClusterRename(cluster.id) }) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Save name")

                Button(action: { cancelClusterRename() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Cancel")
            } else {
                Button(action: { beginClusterRename(cluster) }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Rename project")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Appearance")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("App Mode")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: configBinding(\.appMode)) {
                        ForEach(AppMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                Text(appModeDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if config.appMode != .menubarOnly {
                    settingToggle(
                        "Show in Dock",
                        description: "Display the PromptCraft icon in the macOS Dock.",
                        binding: configBinding(\.showDockIcon)
                    )
                }
            }

            HStack {
                Text("Theme")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: configBinding(\.themePreference)) {
                    Text("System").tag(ThemePreference.system)
                    Text("Light").tag(ThemePreference.light)
                    Text("Dark").tag(ThemePreference.dark)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            settingToggle(
                "Show character count",
                binding: configBinding(\.showCharacterCount)
            )

            settingToggle(
                "Sound on completion",
                binding: configBinding(\.playSoundOnComplete)
            )
        }
    }

    // MARK: - Startup Section

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Startup")

            HStack {
                Text("Launch PromptCraft at login")
                    .font(.system(size: 13))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { config.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Data")

            Button(action: { viewModel.showClearHistoryConfirmation = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                    Text("Clear Prompt History (\(viewModel.historyCount) entries)")
                        .font(.system(size: 13))
                }
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .alert("Clear History?", isPresented: $viewModel.showClearHistoryConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) { viewModel.clearHistory() }
            } message: {
                Text("This will delete all \(viewModel.historyCount) history entries. This cannot be undone.")
            }

            HStack(spacing: 12) {
                Button(action: { viewModel.exportConfiguration() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                        Text("Export Config")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.importConfiguration() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                        Text("Import Config")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
            }

            Button(action: { viewModel.showResetConfirmation = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                    Text("Reset All Settings")
                        .font(.system(size: 13))
                }
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .alert("Reset All Settings?", isPresented: $viewModel.showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { viewModel.resetAllSettings() }
            } message: {
                Text("This will reset all settings to their defaults, remove stored API keys, clear current output, and restart onboarding. This cannot be undone.")
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("App Info")

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                Text("PromptCraft")
                    .font(.system(size: 13, weight: .semibold))
                Text("v\(appVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Link("Website", destination: URL(string: "https://promptcraft.dev")!)
                    .font(.system(size: 11))
                Link("Docs", destination: URL(string: "https://promptcraft.dev/docs")!)
                    .font(.system(size: 11))
                Link("Support", destination: URL(string: "mailto:support@promptcraft.dev")!)
                    .font(.system(size: 11))
            }

            HStack(spacing: 0) {
                Text("Made with \u{2764}\u{FE0F} by ")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Link("Ozzy", destination: URL(string: "https://oguzhanatalay.com")!)
                    .font(.system(size: 11))
            }
            .padding(.top, 4)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var appModeDescription: String {
        switch config.appMode {
        case .menubarOnly:
            return "PromptCraft lives in the menu bar only. Click the icon or use the shortcut to open."
        case .desktopWindow:
            return "PromptCraft opens as a desktop window. Use the shortcut to bring it to front."
        case .both:
            return "Both the menu bar popover and a desktop window are available."
        }
    }

    // MARK: - Extensions Section

    private var extensionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Extensions")

            if !config.localAPIEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("Raycast and Alfred require the Local API. Enable it in the Behavior tab.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Enable") {
                        configService.update { $0.localAPIEnabled = true }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 12)
            }

            extensionRow(
                icon: "bolt.fill", iconColor: .red,
                name: "Raycast",
                subtitle: "Optimize prompts from Raycast launcher",
                statusLabel: config.localAPIEnabled ? "Local API on port \(config.localAPIPort)" : "Requires Local API",
                statusColor: config.localAPIEnabled ? .green : .orange,
                actionLabel: "Get Extension",
                actionURL: "https://www.raycast.com/store"
            )
            sectionDivider
            extensionRow(
                icon: "magnifyingglass", iconColor: .blue,
                name: "Alfred Workflow",
                subtitle: "Optimize with Alfred via hotkey or keyword",
                statusLabel: config.localAPIEnabled ? "Local API on port \(config.localAPIPort)" : "Requires Local API",
                statusColor: config.localAPIEnabled ? .green : .orange,
                actionLabel: "Import Workflow",
                actionURL: "https://www.alfredapp.com/workflows/"
            )
            sectionDivider
            extensionRow(
                icon: "square.grid.2x2.fill", iconColor: .purple,
                name: "Apple Shortcuts",
                subtitle: "Automate prompts with Shortcuts.app and Siri",
                statusLabel: "Built-in via App Intents",
                statusColor: .green,
                actionLabel: "Open Shortcuts",
                actionURL: "shortcuts://"
            )
            sectionDivider
            extensionRow(
                icon: "sparkle.magnifyingglass",
                iconColor: Color(red: 0.2, green: 0.6, blue: 1.0),
                name: "Spotlight",
                subtitle: "Trigger PromptCraft from Spotlight search",
                statusLabel: "Built-in via App Intents",
                statusColor: .green,
                actionLabel: nil,
                actionURL: nil
            )

            if config.localAPIEnabled {
                sectionDivider
                VStack(alignment: .leading, spacing: 6) {
                    Text("API TOKEN")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)
                    Text("Use this token to authenticate Raycast and Alfred.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(localAPIService.getOrCreateToken())
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(localAPITokenCopied ? "Copied!" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(localAPIService.getOrCreateToken(), forType: .string)
                            localAPITokenCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                localAPITokenCopied = false
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(localAPITokenCopied ? .green : Color.accentColor)
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.top, 4)
            }
        }
    }

    private func extensionRow(
        icon: String, iconColor: Color,
        name: String, subtitle: String,
        statusLabel: String, statusColor: Color,
        actionLabel: String?, actionURL: String?
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if let label = actionLabel, let urlStr = actionURL,
                   let url = URL(string: urlStr) {
                    Button(label) { NSWorkspace.shared.open(url) }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 6)
    }


}

// MARK: - Ollama Confetti

private struct OllamaConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var animationPhase = false

    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink, .mint, .cyan, .indigo
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    RoundedRectangle(cornerRadius: particle.isCircle ? particle.size / 2 : 1)
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.isCircle ? particle.size : particle.size * 2.5)
                        .rotationEffect(.degrees(animationPhase ? particle.finalRotation : 0))
                        .offset(
                            x: animationPhase ? particle.finalX : particle.startX,
                            y: animationPhase ? particle.finalY : particle.startY
                        )
                        .opacity(animationPhase ? 0 : 1)
                        .scaleEffect(animationPhase ? 0.3 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                let centerX = geo.size.width / 2
                particles = (0..<40).map { _ in
                    ConfettiParticle(
                        color: colors.randomElement()!,
                        size: CGFloat.random(in: 4...8),
                        isCircle: Bool.random(),
                        startX: centerX - geo.size.width * 0.1 + CGFloat.random(in: 0...geo.size.width * 0.2),
                        startY: -10,
                        finalX: CGFloat.random(in: -geo.size.width * 0.5...geo.size.width * 0.5) + centerX,
                        finalY: CGFloat.random(in: 30...geo.size.height + 40),
                        finalRotation: Double.random(in: -720...720)
                    )
                }
                withAnimation(.easeOut(duration: 2.0)) {
                    animationPhase = true
                }
            }
        }
        .frame(height: 120)
        .clipped()
    }
}

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let color: Color
    let size: CGFloat
    let isCircle: Bool
    let startX: CGFloat
    let startY: CGFloat
    let finalX: CGFloat
    let finalY: CGFloat
    let finalRotation: Double
}

