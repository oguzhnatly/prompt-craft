import Sparkle
import SwiftUI

// MARK: - Navigation

enum PopoverScreen: Equatable {
    case main
    case settings
    case history
    case historyDetail
    case styleManagement
    case styleEditor
    case upgrade
    case templateManagement
    case templateEditor

    var depth: Int {
        switch self {
        case .main: return 0
        case .settings, .history, .upgrade: return 1
        case .historyDetail, .styleManagement, .templateManagement: return 2
        case .styleEditor, .templateEditor: return 3
        }
    }
}

// MARK: - Main Popover View

struct MainPopoverView: View {
    @ObservedObject var viewModel: MainViewModel
    var updater: SPUUpdater?
    @ObservedObject private var configService = ConfigurationService.shared
    @ObservedObject private var onboardingManager = OnboardingManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var trialService = TrialService.shared
    @ObservedObject private var licensingService = LicensingService.shared
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var historyViewModel = HistoryViewModel()
    @ObservedObject private var clipboardHistory = ClipboardHistoryService.shared
    @ObservedObject private var templateService = TemplateService.shared

    // Navigation stack
    @State private var screenStack: [PopoverScreen] = [.main]

    // Style editor state
    @State private var styleEditorViewModel: StyleEditorViewModel?

    // Template editor state
    @State private var templateEditorViewModel: TemplateEditorViewModel?

    // History detail state
    @State private var selectedHistoryEntry: PromptHistoryEntry?

    // Polish states
    @State private var showCopyConfirmation = false
    @State private var showCopyToast = false
    @State private var isOptimizeHovered = false
    @State private var shakeError: CGFloat = 0
    @State private var streamingJustCompleted = false
    @State private var cursorVisible = true
    @FocusState private var isInputFocused: Bool

    // Contextual hint states
    @State private var showInputHint = false
    @State private var showStyleHint = false
    @State private var showCopyHint = false
    @State private var showShortcutCelebration = false

    // Clipboard history
    @State private var showClipboardHistory = false

    // Export menu
    @State private var showExportMenu = false

    // Compare mode
    @State private var showCompareProviderPicker = false

    // Verbosity picker
    @State private var showVerbosityMenu = false
    @State private var verbosityLabelID = UUID()
    @State private var showVerbosityChangeToast = false
    @State private var verbosityChangeMessage = ""

    // Template placeholder editor
    @State private var showTemplatePlaceholders = false

    // Privacy & trial states
    @State private var showPrivacyPopover = false
    @State private var trialNudgeDismissed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isWindowMode) private var isWindowMode

    private let cursorTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    /// Whether the current navigation path is through History (vs Settings).
    private var isHistoryPath: Bool {
        screenStack.contains(.history) || screenStack.contains(.historyDetail)
    }

    /// Whether the current navigation path is through Template Management.
    private var isTemplatePath: Bool {
        screenStack.contains(.templateManagement) || screenStack.contains(.templateEditor)
    }

    private var currentScreen: PopoverScreen {
        screenStack.last ?? .main
    }

    private var shortcutDisplay: String {
        configService.configuration.globalShortcut.displayString
    }

    @ObservedObject private var accessibilityService = AccessibilityService.shared

    private var isAccessibilityGranted: Bool {
        accessibilityService.isAccessibilityGranted
    }

    var body: some View {
        if onboardingManager.shouldShowOnboarding {
            OnboardingView(mainViewModel: viewModel)
        } else {
            mainAppContent
        }
    }

    private var mainAppContent: some View {
        GeometryReader { geometry in
            let slotWidth = isWindowMode ? geometry.size.width : 420
            let slotHeight = isWindowMode ? geometry.size.height : 580

            HStack(spacing: 0) {
                mainContent
                    .frame(width: slotWidth, height: slotHeight)

                // Slot 1 (depth 1): Upgrade, History, or Settings
                Group {
                    if currentScreen == .upgrade {
                        UpgradeView(onBack: { popScreen() })
                    } else if isHistoryPath {
                        HistoryView(
                            viewModel: historyViewModel,
                            onBack: { popScreen() },
                            onSelectEntry: { entry in
                                selectedHistoryEntry = entry
                                pushScreen(.historyDetail)
                            }
                        )
                    } else {
                        SettingsView(
                            isPresented: settingsBackBinding,
                            viewModel: settingsViewModel,
                            onManageStyles: { pushScreen(.styleManagement) },
                            onManageTemplates: { pushScreen(.templateManagement) },
                            updater: updater
                        )
                    }
                }
                .frame(width: slotWidth, height: slotHeight)

                // Slot 2 (depth 2): History Detail, Style Management, or Template Management
                Group {
                    if isHistoryPath {
                        historyDetailPanel
                    } else if isTemplatePath {
                        TemplateManagementView(
                            onBack: { popScreen() },
                            onNewTemplate: { openTemplateEditor(mode: .create) },
                            onEditTemplate: { template in openTemplateEditor(mode: .edit(template.id)) },
                            onViewTemplate: { template in openTemplateEditor(mode: .readOnly(template.id)) }
                        )
                    } else {
                        StyleManagementView(
                            onBack: { popScreen() },
                            onNewStyle: { openStyleEditor(mode: .create) },
                            onEditStyle: { style in openStyleEditor(mode: .edit(style.id)) }
                        )
                    }
                }
                .frame(width: slotWidth, height: slotHeight)

                // Slot 3 (depth 3): Style Editor or Template Editor
                Group {
                    if isTemplatePath {
                        templateEditorPanel
                    } else {
                        styleEditorPanel
                    }
                }
                .frame(width: slotWidth, height: slotHeight)
            }
            .offset(x: CGFloat(-currentScreen.depth) * slotWidth)
            .frame(width: slotWidth, height: slotHeight, alignment: .leading)
            .clipped()
        }
        .frame(
            minWidth: isWindowMode ? nil : 420,
            maxWidth: isWindowMode ? .infinity : 420,
            minHeight: isWindowMode ? nil : 580,
            maxHeight: isWindowMode ? .infinity : 580
        )
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.15)
                : .spring(response: 0.3, dampingFraction: 0.85),
            value: currentScreen
        )
        .onChange(of: currentScreen) { screen in
            if screen == .settings {
                let provider = configService.configuration.selectedProvider
                settingsViewModel.loadAPIKey(for: provider)
                settingsViewModel.loadModels(for: provider)
            }
            if screen == .history {
                historyViewModel.refresh()
            }
        }
        .onExitCommand {
            if currentScreen != .main {
                popScreen()
            } else if viewModel.isProcessing {
                viewModel.cancelOptimization()
            }
        }
        .onReceive(cursorTimer) { _ in
            if viewModel.isProcessing || streamingJustCompleted {
                cursorVisible.toggle()
            }
        }
        .onChange(of: viewModel.isProcessing) { processing in
            if !processing && !viewModel.outputText.isEmpty && viewModel.errorMessage == nil && !viewModel.wasCancelled {
                streamingJustCompleted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    streamingJustCompleted = false
                }
                // Show copy hint on first optimization completion
                if onboardingManager.shouldShowCopyHint {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showCopyHint = true
                        onboardingManager.dismissCopyHint()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        showCopyHint = false
                    }
                }
            }
        }
        .onChange(of: viewModel.selectedStyle?.id) { _ in
            // Show style hint on first style selection
            if onboardingManager.shouldShowStyleHint {
                showStyleHint = true
                onboardingManager.dismissStyleHint()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    showStyleHint = false
                }
            }
            // Dismiss input hint when user interacts
            if showInputHint {
                withAnimation { showInputHint = false }
                onboardingManager.dismissInputHint()
            }
        }
        .onChange(of: viewModel.errorMessage) { error in
            if error != nil {
                // Trigger shake animation
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.3)) {
                    shakeError = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    shakeError = 0
                }
            }
        }
        .onAppear {
            // Start clipboard history monitoring
            ClipboardHistoryService.shared.startMonitoring()

            // Show input hint on first appearance after onboarding
            if onboardingManager.shouldShowInputHint {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showInputHint = true
                }
            }
        }
        .onDisappear {
            ClipboardHistoryService.shared.stopMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.shortcutActivated)) { _ in
            if onboardingManager.shouldShowShortcutCelebration {
                showShortcutCelebration = true
                onboardingManager.dismissShortcutCelebration()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showShortcutCelebration = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.navigateToSettings)) { _ in
            if currentScreen != .settings {
                popToMain()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pushScreen(.settings)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.navigateToUpgrade)) { _ in
            if currentScreen != .upgrade {
                popToMain()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pushScreen(.upgrade)
                }
            }
        }
        // Long input warning alert
        .alert("Long Input", isPresented: $viewModel.showLongInputWarning) {
            Button("Cancel", role: .cancel) { viewModel.cancelLongInputWarning() }
            Button("Continue") { viewModel.confirmLongInputAndOptimize() }
        } message: {
            Text("This input is very long (\(viewModel.longInputCharCount.formatted()) characters). Optimization may take longer and cost more. Continue?")
        }
        // Context engine upgrade notice
        .alert("Context Engine Upgraded", isPresented: Binding(
            get: { ContextEngineService.shared.showUpgradeNotice },
            set: { ContextEngineService.shared.showUpgradeNotice = $0 }
        )) {
            Button("OK") { ContextEngineService.shared.showUpgradeNotice = false }
        } message: {
            Text("Context engine upgraded. Your learned patterns will rebuild as you use PromptCraft.")
        }
        // MARK: - Keyboard Shortcuts
        // Cmd+1 through Cmd+7: select style by position
        .background(
            Group {
                Button("") { viewModel.selectStyleByIndex(0) }
                    .keyboardShortcut("1", modifiers: .command)
                    .hidden()
                Button("") { viewModel.selectStyleByIndex(1) }
                    .keyboardShortcut("2", modifiers: .command)
                    .hidden()
                Button("") { viewModel.selectStyleByIndex(2) }
                    .keyboardShortcut("3", modifiers: .command)
                    .hidden()
                Button("") { viewModel.selectStyleByIndex(3) }
                    .keyboardShortcut("4", modifiers: .command)
                    .hidden()
                Button("") { viewModel.selectStyleByIndex(4) }
                    .keyboardShortcut("5", modifiers: .command)
                    .hidden()
                Button("") { viewModel.selectStyleByIndex(5) }
                    .keyboardShortcut("6", modifiers: .command)
                    .hidden()
                Button("") { viewModel.selectStyleByIndex(6) }
                    .keyboardShortcut("7", modifiers: .command)
                    .hidden()
            }
        )
        .background(
            Group {
                // Cmd+N: New optimization
                Button("") { viewModel.clearAll() }
                    .keyboardShortcut("n", modifiers: .command)
                    .hidden()
                // Cmd+K: Command palette
                Button("") { viewModel.showCommandPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
                    .hidden()
                // Cmd+H: Open history
                Button("") {
                    if currentScreen != .history { popToMain(); pushScreen(.history) }
                }
                    .keyboardShortcut("h", modifiers: .command)
                    .hidden()
                // Cmd+,: Open settings
                Button("") {
                    if currentScreen != .settings { popToMain(); pushScreen(.settings) }
                }
                    .keyboardShortcut(",", modifiers: .command)
                    .hidden()
                // Cmd+Shift+V: Clipboard history
                Button("") { showClipboardHistory.toggle() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                    .hidden()
                // Cmd+?: Keyboard shortcuts overlay
                Button("") { viewModel.showShortcutsOverlay.toggle() }
                    .keyboardShortcut("/", modifiers: [.command, .shift])
                    .hidden()
            }
        )
        // Command Palette overlay
        .sheet(isPresented: $viewModel.showCommandPalette) {
            commandPaletteView
        }
        // Keyboard shortcuts overlay
        .sheet(isPresented: $viewModel.showShortcutsOverlay) {
            keyboardShortcutsOverlay
        }
    }

    // MARK: - History Detail Panel

    @ViewBuilder
    private var historyDetailPanel: some View {
        if let entry = selectedHistoryEntry {
            HistoryDetailView(
                entry: entry,
                viewModel: historyViewModel,
                onBack: {
                    popScreen()
                    selectedHistoryEntry = nil
                },
                onReoptimize: { inputText, styleID in
                    viewModel.prepopulateForReoptimize(input: inputText, styleID: styleID)
                    popToMain()
                    selectedHistoryEntry = nil
                },
                onReoptimizeDifferentStyle: { inputText in
                    viewModel.prepopulateForReoptimize(input: inputText)
                    popToMain()
                    selectedHistoryEntry = nil
                }
            )
        } else {
            Color.clear
        }
    }

    // MARK: - Navigation Helpers

    private func pushScreen(_ screen: PopoverScreen) {
        screenStack.append(screen)
    }

    private func popScreen() {
        if screenStack.count > 1 {
            screenStack.removeLast()
        }
    }

    private func popToMain() {
        screenStack = [.main]
    }

    /// Binding so SettingsView can use its existing back-button logic.
    private var settingsBackBinding: Binding<Bool> {
        Binding(
            get: {
                currentScreen == .settings
                    || currentScreen == .styleManagement
                    || currentScreen == .styleEditor
                    || currentScreen == .templateManagement
                    || currentScreen == .templateEditor
            },
            set: { isPresented in
                if !isPresented { popToMain() }
            }
        )
    }

    private func openStyleEditor(mode: StyleEditorViewModel.Mode) {
        styleEditorViewModel = StyleEditorViewModel(mode: mode)
        pushScreen(.styleEditor)
    }

    // MARK: - Style Editor Panel

    @ViewBuilder
    private var styleEditorPanel: some View {
        if let editorVM = styleEditorViewModel {
            StyleEditorView(
                viewModel: editorVM,
                onBack: { popScreen(); styleEditorViewModel = nil },
                onSaved: { popScreen(); styleEditorViewModel = nil },
                onDuplicateBuiltIn: { copy in
                    styleEditorViewModel = StyleEditorViewModel(mode: .edit(copy.id))
                }
            )
        } else {
            Color.clear
        }
    }

    // MARK: - Template Editor

    private func openTemplateEditor(mode: TemplateEditorViewModel.Mode) {
        templateEditorViewModel = TemplateEditorViewModel(mode: mode)
        pushScreen(.templateEditor)
    }

    @ViewBuilder
    private var templateEditorPanel: some View {
        if let editorVM = templateEditorViewModel {
            TemplateEditorView(
                viewModel: editorVM,
                onBack: { popScreen(); templateEditorViewModel = nil },
                onSaved: { popScreen(); templateEditorViewModel = nil },
                onDuplicateBuiltIn: { copy in
                    templateEditorViewModel = TemplateEditorViewModel(mode: .edit(copy.id))
                }
            )
        } else {
            Color.clear
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ZStack {
            VStack(spacing: 0) {
                headerBar

                // Trial nudge banner
                trialNudgeBanner

                // Network status banner
                if !networkMonitor.isConnected {
                    networkBanner
                }

                // Accessibility revoked banner
                if !accessibilityService.isAccessibilityGranted && onboardingManager.hasCompletedOnboarding {
                    accessibilityRevokedBanner
                }

                Divider()
                inputArea
                if viewModel.inputText.isEmpty {
                    if !viewModel.recentHistoryEntries.isEmpty {
                        recentHistoryCards
                    } else if onboardingManager.shouldShowEmptyStateGuidance {
                        emptyStateGuidance
                    }
                }
                styleSelectorBar
                optimizeButtonArea
                outputArea
                Divider()
                footerBar
            }
            .accessibilityElement(children: .contain)

            // Contextual hint overlays
            contextualHintOverlays
        }
    }

    // MARK: - Network Banner

    private var networkBanner: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
            Text("No internet connection")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.08))
        .accessibilityLabel("No internet connection")
    }

    // MARK: - Accessibility Revoked Banner

    private var accessibilityRevokedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text("Accessibility access was revoked. Some features are unavailable.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Fix") {
                accessibilityService.openAccessibilitySettings()
                accessibilityService.startPollingForPermission()
            }
            .font(.system(size: 11, weight: .medium))
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("PromptCraft")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button(action: { pushScreen(.history) }) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("History")
            .accessibilityLabel("Open history")
            Button(action: { pushScreen(.settings) }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Settings")
            .accessibilityLabel("Open settings")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.inputText)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .disabled(viewModel.isProcessing)
                    .opacity(viewModel.isProcessing ? 0.6 : 1.0)
                    .focused($isInputFocused)
                    .onChange(of: viewModel.inputText) { newText in
                        viewModel.inputTruncationWarning = nil
                        if !newText.isEmpty && showInputHint {
                            withAnimation { showInputHint = false }
                            onboardingManager.dismissInputHint()
                        }
                    }
                    .accessibilityLabel("Prompt input")
                    .accessibilityHint("Enter the text you want to optimize")

                // Placeholder aligned to TextEditor's text origin
                if viewModel.inputText.isEmpty {
                    Text("Type or paste your messy prompt here...")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // Top-right action buttons
                if !viewModel.isProcessing {
                    HStack(spacing: 4) {
                        Spacer()

                        // Clipboard history button
                        if configService.configuration.clipboardHistoryEnabled {
                            Button(action: { showClipboardHistory.toggle() }) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .help("Paste from clipboard history")
                            .accessibilityLabel("Clipboard history")
                            .popover(isPresented: $showClipboardHistory) {
                                clipboardHistoryPopover
                            }
                        }

                        // Clear button
                        if !viewModel.inputText.isEmpty {
                            Button(action: {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    viewModel.inputText = ""
                                    viewModel.clearTemplate()
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear input")
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                    .padding(.top, 4)
                    .padding(.trailing, 2)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: viewModel.inputText.isEmpty)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .innerShadowWell(cornerRadius: 8, focused: isInputFocused)

            if configService.configuration.showCharacterCount || viewModel.inputTruncationWarning != nil {
                HStack(spacing: 8) {
                    if configService.configuration.showCharacterCount {
                        Text("\(viewModel.characterCount) characters")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    if let warning = viewModel.inputTruncationWarning {
                        Text(warning)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Style Selector

    private var styleSelectorBar: some View {
        VStack(spacing: 6) {
            if isWindowMode {
                FlowLayout(spacing: 8) {
                    templatesPill
                    ForEach(viewModel.availableStyles) { style in
                        stylePill(for: style)
                    }
                    addStylePill
                }
                .padding(.horizontal, 16)
                .disabled(viewModel.isProcessing)
                .opacity(viewModel.isProcessing ? 0.6 : 1.0)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Optimization style")
                .accessibilityHint("Select a style for prompt optimization")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        templatesPill
                        ForEach(viewModel.availableStyles) { style in
                            stylePill(for: style)
                        }
                        addStylePill
                    }
                    .padding(.horizontal, 16)
                }
                .scrollGradientEdges()
                .disabled(viewModel.isProcessing)
                .opacity(viewModel.isProcessing ? 0.6 : 1.0)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Optimization style")
                .accessibilityHint("Select a style for prompt optimization")
            }

            // Active template placeholder indicator
            if let template = viewModel.activeTemplate {
                templatePlaceholderBar(template: template)
            }

            // Crossfade style description
            Text(viewModel.selectedStyleDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .id(viewModel.selectedStyle?.id)
                .transition(.opacity)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.2),
                    value: viewModel.selectedStyle?.id
                )
        }
        .padding(.vertical, 6)
    }

    // MARK: - Templates Pill

    private var templatesPill: some View {
        Button(action: { viewModel.showTemplatePicker.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 10))
                Text("Templates")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(viewModel.activeTemplate != nil ? Color.purple.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(viewModel.activeTemplate != nil ? .purple : .secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        viewModel.activeTemplate != nil ? Color.purple.opacity(0.3) : Color(nsColor: .separatorColor),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(BounceTapStyle())
        .focusEffectDisabled()
        .accessibilityLabel("Templates")
        .popover(isPresented: $viewModel.showTemplatePicker) {
            templatePickerPopover
        }
    }

    private func templatePlaceholderBar(template: PromptTemplate) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: template.iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(.purple)
                Text(template.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.purple)
                Spacer()
                Button(action: { showTemplatePlaceholders.toggle() }) {
                    Text(viewModel.areAllPlaceholdersFilled ? "Ready" : "Fill \(template.placeholders.count) fields")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(viewModel.areAllPlaceholdersFilled ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                        .foregroundStyle(viewModel.areAllPlaceholdersFilled ? .green : .orange)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button(action: { viewModel.clearTemplate() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .popover(isPresented: $showTemplatePlaceholders) {
            templatePlaceholderEditor
        }
    }

    private func stylePill(for style: PromptStyle) -> some View {
        let isSelected = viewModel.selectedStyle?.id == style.id
        return Button {
            withAnimation(
                reduceMotion
                    ? .easeInOut(duration: 0.1)
                    : .spring(response: 0.3, dampingFraction: 0.7)
            ) {
                viewModel.selectStyle(style)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: style.iconName)
                    .font(.system(size: 10))
                Text(style.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : Color(nsColor: .separatorColor),
                        lineWidth: 0.5
                    )
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                value: isSelected
            )
        }
        .buttonStyle(BounceTapStyle())
        .focusEffectDisabled()
        .accessibilityLabel("\(style.displayName) style")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityRemoveTraits(isSelected ? [] : .isSelected)
        .contextMenu {
            if !style.isBuiltIn {
                Button("Edit") { openStyleEditor(mode: .edit(style.id)) }
                Button("Duplicate") {
                    StyleService.shared.duplicate(style.id)
                }
                Divider()
            }
            if style.id != DefaultStyles.defaultStyleID {
                Button(style.isEnabled ? "Disable" : "Enable") {
                    if style.isEnabled {
                        StyleService.shared.disable(style.id)
                    } else {
                        StyleService.shared.enable(style.id)
                    }
                }
            }
            if !style.isBuiltIn {
                Divider()
                Button("Delete", role: .destructive) {
                    StyleService.shared.delete(style.id)
                }
            }
        }
    }

    private var addStylePill: some View {
        Button(action: { openStyleEditor(mode: .create) }) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Color(nsColor: .controlBackgroundColor))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        }
        .buttonStyle(BounceTapStyle())
        .focusEffectDisabled()
        .help("Create new style")
        .accessibilityLabel("Create new style")
    }



    // MARK: - Optimize Button

    private var optimizeButtonArea: some View {
        VStack(spacing: 8) {
            // Verbosity chip (tap to cycle, long press for menu)
            complexityChip
                .transition(.opacity.combined(with: .scale(scale: 0.9)))

            Group {
                if trialService.isExpired && !licensingService.isProUser {
                    // Trial expired: show upgrade CTA
                    Button(action: { pushScreen(.upgrade) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 14))
                            Text("Trial Ended. Upgrade to Continue")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(TactileButtonStyle())
                    .focusEffectDisabled()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                } else {
                    VStack(spacing: 8) {
                        // Optimize button
                        Button(action: {
                            if viewModel.isProcessing {
                                viewModel.cancelOptimization()
                            } else {
                                viewModel.optimizePrompt()
                            }
                        }) {
                            HStack(spacing: 6) {
                                if viewModel.isProcessing {
                                    ThreeDotsLoading()
                                    Text("Optimizing...")
                                        .font(.system(size: 14, weight: .semibold))
                                    Spacer()
                                    Text("ESC to cancel")
                                        .font(.system(size: 10))
                                        .opacity(0.7)
                                } else {
                                    Text("Optimize")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("\u{2318}\u{21A9}")
                                        .font(.system(size: 11))
                                        .opacity(0.7)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(optimizeButtonBackground)
                            .foregroundStyle(buttonForeground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shimmer(isActive: viewModel.isProcessing)
                            .buttonPulse(isActive: viewModel.isProcessing)
                        }
                        .buttonStyle(TactileButtonStyle())
                        .focusEffectDisabled()
                        .disabled(!viewModel.isOptimizeEnabled && !viewModel.isProcessing)
                        .keyboardShortcut(.return, modifiers: .command)
                        .animation(
                            reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.8),
                            value: viewModel.isProcessing
                        )
                        .animation(.easeInOut(duration: 0.15), value: viewModel.isOptimizeEnabled)
                        .onHover { hovering in
                            isOptimizeHovered = hovering
                        }
                        .accessibilityLabel(viewModel.isProcessing ? "Cancel optimization" : "Optimize prompt")
                        .accessibilityHint(viewModel.isProcessing ? "Press to cancel the current optimization" : "Press to optimize your prompt with the selected style")
                        .contextMenu {
                            Button(action: { showCompareProviderPicker = true }) {
                                Label("Compare with...", systemImage: "arrow.triangle.branch")
                            }
                        }
                        .popover(isPresented: $showCompareProviderPicker) {
                            compareProviderPicker
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.detectedComplexityTier)
        .animation(.easeInOut(duration: 0.15), value: configService.configuration.outputVerbosity)
    }




    private func cycleVerbosity() {
        let allCases = OutputVerbosity.allCases
        guard let currentIndex = allCases.firstIndex(of: configService.configuration.outputVerbosity) else { return }
        let nextIndex = (currentIndex + 1) % allCases.count
        updateVerbosityMode(allCases[nextIndex])
    }

    private func updateVerbosityMode(_ mode: OutputVerbosity) {
        let currentMode = configService.configuration.outputVerbosity
        guard currentMode != mode else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            configService.update { $0.outputVerbosity = mode }
            verbosityLabelID = UUID()
        }

        guard !viewModel.outputText.isEmpty, !viewModel.isProcessing else { return }
        verbosityChangeMessage = "\(mode.displayName) mode will apply on next optimization"
        withAnimation(.easeInOut(duration: 0.15)) {
            showVerbosityChangeToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            withAnimation(.easeInOut(duration: 0.15)) {
                showVerbosityChangeToast = false
            }
        }
    }

    private var complexityChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: 5, height: 5)
            Text(configService.configuration.outputVerbosity.displayName)
                .id(verbosityLabelID)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.accentColor)
            if viewModel.complexityContextBoosted {
                Image(systemName: "brain")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.08))
        )
        .onTapGesture {
            cycleVerbosity()
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            showVerbosityMenu = true
        }
        .popover(isPresented: $showVerbosityMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(OutputVerbosity.allCases, id: \.self) { mode in
                    Button(action: {
                        updateVerbosityMode(mode)
                        showVerbosityMenu = false
                    }) {
                        HStack(spacing: 8) {
                            Text(mode == .concise ? "\(mode.displayName) (recommended)" : mode.displayName)
                                .font(.system(size: 12))
                            Spacer()
                            if configService.configuration.outputVerbosity == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    if mode != .detailed {
                        Divider().padding(.horizontal, 8)
                    }
                }
            }
            .frame(width: 200)
            .padding(.vertical, 4)
        }
        .accessibilityLabel("Output verbosity: \(configService.configuration.outputVerbosity.displayName)")
        .accessibilityHint("Tap to cycle, long press for options")
    }

    @ViewBuilder
    private var optimizeButtonBackground: some View {
        if viewModel.isProcessing {
            LinearGradient(
                colors: [Color.orange.opacity(0.9), Color.orange.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if viewModel.isOptimizeEnabled {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(isOptimizeHovered ? 1.0 : 0.95),
                    Color.accentColor.opacity(isOptimizeHovered ? 0.9 : 0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Color(nsColor: .controlBackgroundColor)
        }
    }

    private var buttonForeground: Color {
        if viewModel.isProcessing { return .white }
        return viewModel.isOptimizeEnabled ? .white : .secondary
    }

    // MARK: - Output Area

    private var outputArea: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ZStack {
                if let error = viewModel.errorMessage {
                    // Error state with red tint and shake
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.system(size: 16))
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.leading)
                        }

                        // Action buttons for specific errors
                        if viewModel.errorSuggestsSettings {
                            Button(action: { pushScreen(.settings) }) {
                                Text("Open Settings")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.1))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        // Retry button for partial responses
                        if viewModel.isPartialResponse {
                            Button(action: {
                                viewModel.optimizePrompt()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10))
                                    Text("Retry")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.05))
                    .modifier(ShakeEffect(animatableData: shakeError))
                } else if viewModel.outputText.isEmpty && !viewModel.isProcessing {
                    if onboardingManager.needsAPIKeyReminder && viewModel.errorMessage == nil
                        && !(trialService.isExpired && !licensingService.isProUser) {
                        // API key reminder card (hide when trial is expired — upgrade CTA shown instead)
                        apiKeyReminderCard
                    } else {
                        // Empty state with pulsing
                        VStack(spacing: 8) {
                            Image(systemName: "text.quote")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text("Your optimized prompt will appear here")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 13))
                        }
                        .pulsingOpacity()
                        .accessibilityLabel("Output area. Your optimized prompt will appear here.")
                    }
                } else {
                    // Streaming/completed output with cursor
                    ZStack(alignment: .bottom) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                                        Text(viewModel.outputText)
                                            .font(.system(size: 13, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        if viewModel.isProcessing || streamingJustCompleted {
                                            BlinkingCursorView(isStreaming: viewModel.isProcessing)
                                                .padding(.leading, 1)
                                        }
                                    }
                                    .padding(4)

                                    if viewModel.wasCancelled {
                                        Text("(cancelled)")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.orange)
                                            .padding(.top, 4)
                                            .padding(.leading, 4)
                                    }

                                    if viewModel.isPartialResponse {
                                        Text("(partial result, connection lost)")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.orange)
                                            .padding(.top, 4)
                                            .padding(.leading, 4)
                                    }

                                    Color.clear
                                        .frame(height: 1)
                                        .id("bottom")
                                }
                            }
                            .onChange(of: viewModel.outputText) { _ in
                                if viewModel.isProcessing {
                                    withAnimation(.easeOut(duration: 0.05)) {
                                        proxy.scrollTo("bottom", anchor: .bottom)
                                    }
                                }
                            }
                        }

                        // Toast overlay for copy confirmation
                        ToastOverlay(
                            message: "Copied to clipboard",
                            icon: "checkmark.circle.fill",
                            isShowing: showCopyToast
                        )

                        VStack {
                            if showVerbosityChangeToast {
                                HStack(spacing: 6) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(verbosityChangeMessage)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .padding(.top, 8)
                                .transition(.opacity)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .innerShadowWell(cornerRadius: 8)
            .overlay(alignment: .topTrailing) {
                if let mode = viewModel.outputVerbosityUsed, !viewModel.outputText.isEmpty {
                    Text(mode.badgeSymbol)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.75))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))
                        .clipShape(Capsule())
                        .padding(.top, 6)
                        .padding(.trailing, 6)
                }
            }

            // Streaming privacy indicator
            streamingPrivacyIndicator

            // Context transparency indicator
            if viewModel.contextUsed && !viewModel.isProcessing && !viewModel.outputText.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                    Text("\(viewModel.contextEntryCount) context entr\(viewModel.contextEntryCount == 1 ? "y" : "ies") used")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.1))
                .clipShape(Capsule())
                .help("Relevant context from your previous optimizations was included to improve this result.")
                .transition(.opacity)
            }

            // Verbose output badge + compress button
            if viewModel.isOutputVerbose && !viewModel.isProcessing {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                    Text("Output exceeded word limit")
                        .font(.system(size: 10, weight: .medium))

                    if viewModel.isCompressing {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                    } else {
                        Button(action: { viewModel.compressOutput() }) {
                            Text("Compress")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(Capsule())
                    }
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .clipShape(Capsule())
                .transition(.opacity)
            }

            // Paused context indicator when trial expired
            if trialService.isExpired && !licensingService.isProUser && trialService.contextEntryCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                    Text("Context engine: \(trialService.contextEntryCount) learned patterns (paused)")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())
            }

            // Compare results view
            if viewModel.isCompareMode && !viewModel.compareResults.isEmpty {
                compareResultsView
            }

            // Explanation panel
            if viewModel.showExplanation, let explanation = viewModel.currentExplanation {
                ExplanationView(explanation: explanation)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !viewModel.outputText.isEmpty && !viewModel.isProcessing {
                HStack(spacing: 8) {
                    if viewModel.clipboardCopiedNotification && !showCopyToast {
                        HStack(spacing: 3) {
                            Image(systemName: "clipboard.fill")
                                .font(.system(size: 10))
                            Text("On clipboard")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary.opacity(0.7))
                        .transition(.opacity)
                    } else if viewModel.isOutputOnClipboard && !showCopyToast {
                        HStack(spacing: 3) {
                            Image(systemName: "clipboard.fill")
                                .font(.system(size: 10))
                            Text("On clipboard")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary.opacity(0.7))
                    }

                    Spacer()

                    // Explain toggle
                    if configService.configuration.explainModeEnabled {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.showExplanation.toggle()
                            }
                        }) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(viewModel.showExplanation ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .help("Toggle pipeline explanation")
                        .accessibilityLabel(viewModel.showExplanation ? "Hide explanation" : "Show explanation")
                    }

                    // Export dropdown
                    Menu {
                        ForEach(ExportFormat.clipboardFormats, id: \.self) { format in
                            Button(action: { exportOutput(as: format) }) {
                                Label(format.menuLabel, systemImage: format.iconName)
                            }
                        }
                        Divider()
                        Button(action: { viewModel.saveOutputToFile() }) {
                            Label("Save to File...", systemImage: "square.and.arrow.down")
                        }
                        Divider()
                        Section("Save as System Prompt") {
                            ForEach(SystemPromptDestination.allCases, id: \.self) { destination in
                                Button(action: { viewModel.exportAsSystemPrompt(destination: destination) }) {
                                    Label(destination.menuLabel, systemImage: destination.iconName)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .focusEffectDisabled()
                    .help("Export output")
                    .accessibilityLabel("Export output in different formats")

                    if !viewModel.isOutputOnClipboard || showCopyConfirmation {
                        Button(action: { copyOutput() }) {
                            Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundStyle(showCopyConfirmation ? .green : .secondary)
                                .scaleEffect(showCopyConfirmation ? 1.1 : 1.0)
                                .animation(
                                    reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.5),
                                    value: showCopyConfirmation
                                )
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .accessibilityLabel(showCopyConfirmation ? "Copied" : "Copy output to clipboard")
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                    }

                    Button(action: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            viewModel.clearOutput()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .accessibilityLabel("Clear output")
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.clipboardCopiedNotification)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isOutputOnClipboard)
                .animation(.easeInOut(duration: 0.2), value: showCopyConfirmation)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 8) {
            // Left: shortcut or accessibility warning
            if !isAccessibilityGranted {
                Button(action: {
                    AccessibilityService.shared.openAccessibilitySettings()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text("\(shortcutDisplay) unavailable")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Grant accessibility access to enable \(shortcutDisplay) shortcut")
            } else {
                Text("\(shortcutDisplay) to toggle")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Center: trial counter pill
            trialCounterPill

            Spacer()

            // Right: privacy indicator
            Button(action: { showPrivacyPopover.toggle() }) {
                HStack(spacing: 3) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 9))
                    Text("Local & Private")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPrivacyPopover) {
                privacyInfoPopover
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: - Trial Counter Pill

    @ViewBuilder
    private var trialCounterPill: some View {
        if licensingService.isProUser {
            HStack(spacing: 3) {
                Image(systemName: licensingService.licenseType == .cloud ? "cloud.fill" : "star.fill")
                    .font(.system(size: 8))
                Text(licensingService.licenseType == .cloud ? "Cloud" : "Pro")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.1))
            .clipShape(Capsule())
        } else if trialService.isExpired {
            Button(action: { pushScreen(.upgrade) }) {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                    Text("Trial ended")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        } else if case .active(let days) = trialService.trialState {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.system(size: 8))
                Text("Trial: \(days) day\(days == 1 ? "" : "s") left")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(days <= 4 ? .orange : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((days <= 4 ? Color.orange : Color.secondary).opacity(0.1))
            .clipShape(Capsule())
        }
    }

    // MARK: - Trial Nudge Banner

    @ViewBuilder
    private var trialNudgeBanner: some View {
        if !licensingService.isProUser && !trialNudgeDismissed {
            if trialService.isExpired || trialService.shouldShowWarning {
                // Day 13+ or expired: amber warning
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    if trialService.isExpired {
                        Text("Your trial has ended. Upgrade to continue optimizing.")
                    } else {
                        Text("Your trial ends tomorrow. Don't lose your \(trialService.contextEntryCount) learned patterns.")
                    }
                    Spacer()
                    Button("Upgrade Now") { pushScreen(.upgrade) }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.orange.opacity(0.9))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.12))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color.orange.opacity(0.25)),
                    alignment: .bottom
                )
            } else if trialService.shouldShowNudge {
                // Day 10-12: gentle nudge
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 11))
                        .foregroundStyle(.purple)
                    if trialService.contextEntryCount > 0 {
                        Text("\(trialService.contextEntryCount) patterns learned, \(trialService.daysRemaining) days left in trial")
                    } else {
                        Text("\(trialService.daysRemaining) days left in trial")
                    }
                    Spacer()
                    Button("Upgrade") { pushScreen(.upgrade) }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Button(action: {
                        trialNudgeDismissed = true
                        UserDefaults.standard.set(
                            Date().timeIntervalSince1970,
                            forKey: AppConstants.UserDefaultsKeys.trialNudgeDismissedDate
                        )
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.05))
            }
        }
    }

    // MARK: - Privacy Info Popover

    private var privacyInfoPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                Text("Privacy")
                    .font(.system(size: 13, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Context entries")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(ContextEngineService.shared.entryCount)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Estimated disk size")
                        .font(.system(size: 12))
                    Spacer()
                    Text(estimatedDiskSize)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Your data never leaves this Mac")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 12) {
                Button(action: exportAllData) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10))
                        Text("Export My Data")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .foregroundStyle(Color.accentColor)

                Button(action: { showDeleteDataConfirmation = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("Delete All Data")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(width: 260)
        .focusEffectDisabled()
        .alert("Delete All Data?", isPresented: $showDeleteDataConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteAllData() }
        } message: {
            Text("This will permanently delete all context entries, history, and settings. This cannot be undone.")
        }
    }

    @State private var showDeleteDataConfirmation = false

    private var estimatedDiskSize: String {
        let entries = ContextEngineService.shared.entryCount
        let historyEntries = HistoryService.shared.entries.count
        let estimatedKB = (entries * 2) + (historyEntries * 1) + 10
        if estimatedKB > 1024 {
            return String(format: "%.1f MB", Double(estimatedKB) / 1024.0)
        }
        return "\(estimatedKB) KB"
    }

    private func exportAllData() {
        // Lock popover so the save panel doesn't dismiss it
        NotificationCenter.default.post(
            name: AppConstants.Notifications.lockPopover,
            object: nil,
            userInfo: ["locked": true]
        )
        defer {
            NotificationCenter.default.post(
                name: AppConstants.Notifications.lockPopover,
                object: nil,
                userInfo: ["locked": false]
            )
        }

        let exportData: [String: Any] = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "historyCount": HistoryService.shared.entries.count,
            "contextEntryCount": ContextEngineService.shared.entryCount,
            "clusterCount": ContextEngineService.shared.clusters.count,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PromptCraft-data-export.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? jsonData.write(to: url)
        }
    }

    private func deleteAllData() {
        ContextEngineService.shared.clearAllData()
        HistoryService.shared.clearAll()
        showDeleteDataConfirmation = false
    }

    // MARK: - Streaming Privacy Indicator

    @ViewBuilder
    private var streamingPrivacyIndicator: some View {
        if viewModel.isProcessing {
            let providerName = configService.configuration.selectedProvider.displayName
            let isCloud = configService.configuration.selectedProvider == .promptCraftCloud
            HStack(spacing: 3) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                Text(isCloud ? "Via PromptCraft Cloud (no data stored)" : "Direct to \(providerName)")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.secondary.opacity(0.6))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Recent History Cards

    private var recentHistoryCards: some View {
        VStack(spacing: 6) {
            ForEach(viewModel.recentHistoryEntries) { entry in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.prepopulateForReoptimize(input: entry.inputText, styleID: entry.styleID)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.styleIconName(for: entry.styleID))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(recentCardPreview(entry.inputText))
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(viewModel.styleDisplayName(for: entry.styleID))
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.3)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recent optimization: \(recentCardPreview(entry.inputText))")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: viewModel.inputText.isEmpty)
    }

    private func recentCardPreview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count > 50 {
            return String(singleLine.prefix(50)) + "..."
        }
        return singleLine
    }

    // MARK: - Empty State Guidance

    private var emptyStateGuidance: some View {
        VStack(spacing: 6) {
            Text("Try These")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(samplePrompts, id: \.text) { sample in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.inputText = sample.text
                        if let style = viewModel.availableStyles.first(where: { $0.id == sample.styleID }) {
                            viewModel.selectStyle(style)
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: sample.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                        Text(sample.text)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(sample.styleName)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.3)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .transition(.opacity)
    }

    private var samplePrompts: [(text: String, styleName: String, icon: String, styleID: UUID)] {
        [
            (
                text: "make an api endpoint that handles user registration with validation",
                styleName: "Engineering",
                icon: "hammer",
                styleID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            ),
            (
                text: "research the current state of quantum computing for business applications",
                styleName: "Research",
                icon: "magnifyingglass",
                styleID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
            ),
            (
                text: "write a blog post about productivity tips for remote workers",
                styleName: "Content",
                icon: "doc.text",
                styleID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
            ),
        ]
    }

    // MARK: - API Key Reminder Card

    private var apiKeyReminderCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)

            Text("To optimize prompts, connect an AI provider.")
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Button(action: {
                pushScreen(.settings)
            }) {
                Text("Set Up Now")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(TactileButtonStyle())
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                .background(Color.accentColor.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        )
    }

    // MARK: - Contextual Hint Overlays

    @ViewBuilder
    private var contextualHintOverlays: some View {
        // Input area hint
        if showInputHint && viewModel.inputText.isEmpty && !viewModel.isProcessing {
            contextualHint(
                text: "Start typing or paste text here.",
                alignment: .top
            )
            .onTapGesture {
                withAnimation { showInputHint = false }
                onboardingManager.dismissInputHint()
            }
        }

        // Style selection hint
        if showStyleHint {
            contextualHint(
                text: "Each style optimizes your prompt differently. Try a few!",
                alignment: .center
            )
            .onTapGesture {
                withAnimation { showStyleHint = false }
                onboardingManager.dismissStyleHint()
            }
        }

        // Copy button hint
        if showCopyHint {
            contextualHint(
                text: configService.configuration.autoCopyToClipboard
                    ? "Your optimized prompt is ready. It's already on your clipboard."
                    : "Your optimized prompt is ready. Click to copy.",
                alignment: .bottom
            )
            .onTapGesture {
                withAnimation { showCopyHint = false }
                onboardingManager.dismissCopyHint()
            }
        }

        // Shortcut celebration
        if showShortcutCelebration {
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.system(size: 12))
                    Text("Nice! You used the shortcut.")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                .padding(.bottom, 40)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }
            .animation(
                reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.35, dampingFraction: 0.8),
                value: showShortcutCelebration
            )
        }
    }

    private func contextualHint(text: String, alignment: Alignment) -> some View {
        ZStack(alignment: alignment) {
            // Dismissible background
            Color.black.opacity(0.01)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            .padding(alignment == .top ? .top : (alignment == .bottom ? .bottom : []), 60)
            .padding(.horizontal, 20)
            .transition(.opacity)
        }
    }

    // MARK: - Clipboard History Popover

    private var clipboardHistoryPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Clipboard History")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if !clipboardHistory.items.isEmpty {
                    Button("Clear") { clipboardHistory.clearHistory() }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .focusEffectDisabled()
                }
            }

            if clipboardHistory.recentItems.isEmpty {
                Text("No clipboard history yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(clipboardHistory.recentItems) { item in
                            Button(action: {
                                viewModel.inputText += item.text
                                showClipboardHistory = false
                            }) {
                                HStack(spacing: 8) {
                                    Text(item.preview)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(item.timestampString)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    // MARK: - Template Picker Popover

    private var templatePickerPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Templates")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(templateService.templates) { template in
                        Button(action: {
                            viewModel.applyTemplate(template)
                            showTemplatePlaceholders = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: template.iconName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(template.description)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if template.isBuiltIn {
                                    Text("Built-in")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                    }
                }
            }
            .frame(maxHeight: 300)

            Divider()

            Button(action: {
                viewModel.showTemplatePicker = false
                pushScreen(.settings)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pushScreen(.templateManagement)
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "gear")
                        .font(.system(size: 11))
                    Text("Manage Templates")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .padding(12)
        .frame(width: 340)
    }

    // MARK: - Template Placeholder Editor

    private var templatePlaceholderEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let template = viewModel.activeTemplate {
                HStack {
                    Image(systemName: template.iconName)
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                    Text(template.name)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(template.placeholders, id: \.self) { placeholder in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(placeholder.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                TextField("Enter \(placeholder.replacingOccurrences(of: "_", with: " "))...",
                                          text: Binding(
                                              get: { viewModel.templatePlaceholderValues[placeholder] ?? "" },
                                              set: { viewModel.templatePlaceholderValues[placeholder] = $0 }
                                          ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        viewModel.clearTemplate()
                        showTemplatePlaceholders = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button(action: {
                        viewModel.assembleTemplate()
                        showTemplatePlaceholders = false
                    }) {
                        Text("Apply Template")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(viewModel.areAllPlaceholdersFilled ? Color.accentColor : Color.secondary.opacity(0.3))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.areAllPlaceholdersFilled)
                }
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: - Compare Provider Picker

    private var compareProviderPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compare Providers")
                .font(.system(size: 13, weight: .semibold))

            Text("Select 2-3 providers to compare results side-by-side.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            let statuses = LLMProviderManager.shared.allProviderStatuses()
            ForEach(statuses, id: \.provider) { status in
                Toggle(isOn: Binding(
                    get: { viewModel.compareProviders.contains(status.provider) },
                    set: { selected in
                        if selected {
                            if viewModel.compareProviders.count < 3 {
                                viewModel.compareProviders.append(status.provider)
                            }
                        } else {
                            viewModel.compareProviders.removeAll { $0 == status.provider }
                        }
                    }
                )) {
                    HStack(spacing: 6) {
                        Text(status.displayName)
                            .font(.system(size: 12))
                        if !status.hasAPIKey {
                            Text("No key")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!status.hasAPIKey)
            }

            HStack {
                Spacer()
                Button(action: {
                    showCompareProviderPicker = false
                    viewModel.isCompareMode = true
                    viewModel.startComparison()
                }) {
                    Text("Compare (\(viewModel.compareProviders.count))")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(viewModel.compareProviders.count >= 2 ? Color.accentColor : Color.secondary.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.compareProviders.count < 2)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: - Compare Results View

    private var compareResultsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Comparison Results")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isComparing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                }
                Button(action: {
                    viewModel.isCompareMode = false
                    viewModel.compareResults = []
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.compareResults) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(result.providerName)
                                    .font(.system(size: 11, weight: .semibold))
                                Spacer()
                                if result.isComplete {
                                    if result.error != nil {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.red)
                                    } else {
                                        Text("\(result.durationMs)ms")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    ThreeDotsLoading()
                                }
                            }

                            if let error = result.error {
                                Text(error)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                            } else {
                                Text(result.outputText.isEmpty ? "Waiting..." : String(result.outputText.prefix(150)) + (result.outputText.count > 150 ? "..." : ""))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(5)
                            }

                            if result.isComplete && result.error == nil {
                                HStack {
                                    Text("\u{2248}\(result.tokenCount) tokens")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                    Button("Use This") {
                                        viewModel.useCompareResult(result)
                                    }
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(8)
                        .frame(width: isWindowMode ? 220 : 180)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.3)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 4)
    }

    // MARK: - Command Palette

    private var commandPaletteView: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                TextField("Search styles, templates, actions...", text: $viewModel.commandPaletteQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                if !viewModel.commandPaletteQuery.isEmpty {
                    Button(action: { viewModel.commandPaletteQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Results
            ScrollView {
                VStack(spacing: 2) {
                    let results = viewModel.commandPaletteResults()
                    if results.isEmpty {
                        Text("No results")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(results) { item in
                            Button(action: {
                                item.action()
                                viewModel.showCommandPalette = false
                                viewModel.commandPaletteQuery = ""
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: item.iconName)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(item.subtitle)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 360, height: 380)
        .onAppear {
            viewModel.commandPaletteQuery = ""
        }
    }

    // MARK: - Keyboard Shortcuts Overlay

    private var keyboardShortcutsOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { viewModel.showShortcutsOverlay = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            let shortcuts: [(String, String)] = [
                ("\u{2318}\u{21A9}", "Optimize prompt"),
                ("\u{2318}1-7", "Select style by position"),
                ("\u{2318}\u{21E7}C", "Copy output"),
                ("\u{2318}\u{21E7}V", "Clipboard history"),
                ("\u{2318}K", "Command palette"),
                ("\u{2318}N", "New optimization"),
                ("\u{2318}H", "Open history"),
                ("\u{2318},", "Open settings"),
                ("\u{2318}\u{21E7}/", "Show shortcuts"),
                ("Esc", "Cancel / go back"),
            ]

            VStack(spacing: 6) {
                ForEach(shortcuts, id: \.0) { shortcut in
                    HStack {
                        Text(shortcut.0)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 70, alignment: .trailing)
                        Text(shortcut.1)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Actions

    private func copyOutput() {
        viewModel.copyOutputToClipboard()

        // Icon morph animation
        showCopyConfirmation = true

        // Toast animation
        showCopyToast = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopyConfirmation = false
            showCopyToast = false
        }
    }

    private func exportOutput(as format: ExportFormat) {
        viewModel.exportOutput(as: format)

        showCopyConfirmation = true
        showCopyToast = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopyConfirmation = false
            showCopyToast = false
        }
    }
}
