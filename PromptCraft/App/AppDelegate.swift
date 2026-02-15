import AppKit
import Carbon.HIToolbox
import Combine
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let viewModel = MainViewModel()
    private let shortcutManager = GlobalShortcutManager.shared
    private let clipboardService = ClipboardService.shared
    private var cancellables = Set<AnyCancellable>()
    private var rightClickMonitor: Any?
    private let accessibilityService = AccessibilityService.shared
    private var previousAccessibilityState: Bool = false
    private var animationTimer: Timer?
    private var animationFrames: [NSImage] = []
    private var animationFrameIndex = 0
    private var desktopWindowController: DesktopWindowController?

    /// Sparkle updater controller for automatic and manual update checks.
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("PromptCraft launched")

        // Single-instance enforcement
        guard enforceSingleInstance() else {
            Logger.shared.info("Another instance is running; quitting")
            NSApp.terminate(nil)
            return
        }

        // Initialize services (triggers lazy loading of singletons)
        _ = ConfigurationService.shared
        _ = StyleService.shared
        _ = HistoryService.shared
        _ = NetworkMonitor.shared
        _ = ContextEngineService.shared
        _ = NotificationService.shared
        _ = InlineOverlayController.shared
        _ = TrialService.shared
        _ = LicensingService.shared

        setupStatusItem()
        setupPopover()
        registerGlobalShortcut()
        observeProcessingState()

        // Request notification permission on first launch
        NotificationService.shared.requestPermissionIfNeeded()

        // Listen for close-popover notifications (e.g., from Quick Optimize auto-close).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClosePopover),
            name: AppConstants.Notifications.closePopover,
            object: nil
        )

        // Listen for lock/unlock popover notifications (e.g., when file panels open).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLockPopover(_:)),
            name: AppConstants.Notifications.lockPopover,
            object: nil
        )

        // Listen for overlay → popover text pre-loading.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenPopoverWithText(_:)),
            name: AppConstants.Notifications.openPopoverWithText,
            object: nil
        )

        // Listen for navigateToSettings (from context menu or overlay).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigateToSettings),
            name: AppConstants.Notifications.navigateToSettings,
            object: nil
        )

        // Track accessibility state for detecting revocation
        previousAccessibilityState = accessibilityService.isAccessibilityGranted
        observeAccessibilityChanges()

        // Register URL scheme handler for promptcraft:// deep links
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Apply theme
        applyTheme(ConfigurationService.shared.configuration.themePreference)
        observeThemeChanges()
        observeSystemAppearance()

        // Desktop window controller
        desktopWindowController = DesktopWindowController(viewModel: viewModel, updater: updaterController.updater)
        applyAppMode(ConfigurationService.shared.configuration.appMode)
        observeAppModeChanges()

        // Listen for openDesktopWindow notifications (from context menu).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenDesktopWindow),
            name: AppConstants.Notifications.openDesktopWindow,
            object: nil
        )

        // Check for restart state restoration
        handleRestartStateRestoration()

        Logger.shared.info("Initialization complete")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let mode = ConfigurationService.shared.configuration.appMode
        switch mode {
        case .desktopWindow, .both:
            desktopWindowController?.showWindow()
        case .menubarOnly:
            if let button = statusItem?.button {
                showPopover(relativeTo: button)
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.info("PromptCraft terminating")
        shortcutManager.unregister()
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Single Instance

    /// Returns `true` if this is the only running instance.
    /// If another instance is found, activates it and returns `false`.
    private func enforceSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? AppConstants.bundleIdentifier
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let others = runningApps.filter { $0 != NSRunningApplication.current }

        if let existing = others.first {
            existing.activate()
            return false
        }
        return true
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = MenuBarIconGenerator.createSparkleIcon()
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(togglePopover)
            button.target = self
            // Only fire action on left-click so right-click can show context menu
            button.sendAction(on: .leftMouseUp)
        }

        // Monitor for right-clicks on the status item button
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseUp) { [weak self] event in
            guard let self, let button = self.statusItem?.button else { return event }
            let locationInButton = button.convert(event.locationInWindow, from: nil)
            if button.bounds.contains(locationInButton) {
                self.showContextMenu()
                return nil // consume the event
            }
            return event
        }
    }

    // MARK: - Processing State Observation

    /// Observe both the popover view model and inline overlay processing states
    /// to update the menubar icon with an animated sparkle.
    private func observeProcessingState() {
        let inlineController = InlineOverlayController.shared

        viewModel.$isProcessing
            .combineLatest(inlineController.$isQuickProcessing, inlineController.$isOptimizeProcessing)
            .map { popover, quick, optimize in popover || quick || optimize }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] anyProcessing in
                self?.updateMenuBarAnimation(processing: anyProcessing)
            }
            .store(in: &cancellables)
    }

    private func updateMenuBarAnimation(processing: Bool) {
        guard let button = statusItem?.button else { return }

        if processing {
            startMenuBarAnimation(button: button)
        } else {
            stopMenuBarAnimation(button: button)
        }
    }

    private func startMenuBarAnimation(button: NSStatusBarButton) {
        guard animationTimer == nil else { return }

        animationFrames = MenuBarIconGenerator.createAnimationFrames()
        animationFrameIndex = 0

        // Set first frame immediately
        button.image = animationFrames[0]
        button.image?.size = NSSize(width: 18, height: 18)

        // If reduce motion returned a single frame, don't animate
        guard animationFrames.count > 1 else { return }

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            guard let self, let button = self.statusItem?.button else { return }
            self.animationFrameIndex = (self.animationFrameIndex + 1) % self.animationFrames.count
            button.image = self.animationFrames[self.animationFrameIndex]
            button.image?.size = NSSize(width: 18, height: 18)
        }
    }

    private func stopMenuBarAnimation(button: NSStatusBarButton) {
        animationTimer?.invalidate()
        animationTimer = nil
        animationFrames = []
        animationFrameIndex = 0

        button.image = MenuBarIconGenerator.createSparkleIcon()
        button.image?.size = NSSize(width: 18, height: 18)
    }

    // MARK: - Popover Setup

    private func setupPopover() {
        let contentVC = NSViewController()
        let hostingView = NSHostingView(rootView: MainPopoverView(viewModel: viewModel, updater: updaterController.updater))

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        contentVC.view = visualEffect
        contentVC.preferredContentSize = NSSize(width: 420, height: 580)

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 420, height: 580)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.contentViewController = contentVC

        // Apply theme to popover view so it persists across open/close cycles
        // Always resolve to explicit appearance to avoid NSVisualEffectView rendering
        // differences between system-inherited (nil) and explicitly-set appearances
        let themeAppearance = ConfigurationService.shared.configuration.themePreference.nsAppearance
            ?? Self.resolvedSystemAppearance()
        visualEffect.appearance = themeAppearance
    }

    // MARK: - Global Shortcut

    private func registerGlobalShortcut() {
        shortcutManager.onShortcutActivated = { [weak self] in
            self?.handleShortcutActivation()
        }
        shortcutManager.register()
    }

    private func handleShortcutActivation() {
        // Notify the UI that the shortcut was used (for onboarding celebration)
        NotificationCenter.default.post(name: AppConstants.Notifications.shortcutActivated, object: nil)

        let config = ConfigurationService.shared.configuration

        switch config.appMode {
        case .desktopWindow:
            // Desktop-only mode: bring window to front
            desktopWindowController?.showWindow()
            return

        case .menubarOnly, .both:
            // Menubar or Both: toggle popover (window is independent in Both mode)
            guard let popover = popover, let button = statusItem?.button else { return }

            if popover.isShown {
                popover.performClose(nil)
                return
            }

            // Auto-capture selected text mode: simulate Cmd+C then read clipboard.
            if config.autoCaptureSelectedText {
                clipboardService.captureSelectedText { [weak self] capturedText in
                    guard let self else { return }
                    self.openPopoverWithClipboard(text: capturedText, button: button)
                }
            } else if config.clipboardCaptureEnabled {
                // Simple clipboard read mode.
                let text = clipboardService.readText()
                openPopoverWithClipboard(text: text, button: button)
            } else {
                // No clipboard capture — just open.
                showPopover(relativeTo: button)
            }
        }
    }

    private func openPopoverWithClipboard(text: String?, button: NSStatusBarButton) {
        if let text, !text.isEmpty {
            viewModel.populateFromClipboard(text)
        }
        showPopover(relativeTo: button)

        // Quick Optimize: auto-start optimization if enabled and we have input.
        let config = ConfigurationService.shared.configuration
        if config.quickOptimizeEnabled && !viewModel.inputText.isEmpty {
            viewModel.optimizePrompt()
        }
    }

    // MARK: - Popover Management

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover(relativeTo: button)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        guard let popover, !popover.isShown else { return }

        // Silently re-check accessibility permission each time the popover opens
        accessibilityService.recheckPermission()

        // Detect revocation: was granted, now isn't
        let currentState = accessibilityService.isAccessibilityGranted
        if previousAccessibilityState && !currentState {
            Logger.shared.info("Accessibility access was revoked")
        }
        previousAccessibilityState = currentState

        // Refresh trial status and re-validate license on each open
        TrialService.shared.checkTrialStatus()
        LicensingService.shared.revalidateIfNeeded()

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func handleClosePopover() {
        popover?.performClose(nil)
    }

    @objc private func handleLockPopover(_ notification: Notification) {
        let locked = (notification.userInfo?["locked"] as? Bool) ?? false
        popover?.behavior = locked ? .applicationDefined : .transient
    }

    // MARK: - Overlay / Settings Navigation

    @objc private func handleOpenPopoverWithText(_ notification: Notification) {
        guard let text = notification.userInfo?["text"] as? String,
              let button = statusItem?.button else { return }

        let autoOptimize = (notification.userInfo?["autoOptimize"] as? Bool) ?? false

        viewModel.populateFromClipboard(text)
        showPopover(relativeTo: button)

        if autoOptimize {
            // Brief delay to let the popover appear before starting optimization
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.viewModel.optimizePrompt()
            }
        }
    }

    @objc private func handleNavigateToSettings() {
        guard let button = statusItem?.button else { return }
        // Just open the popover — MainPopoverView listens for this notification too
        // and will navigate to settings screen
        showPopover(relativeTo: button)
    }

    // MARK: - Accessibility State Observation

    private func observeAccessibilityChanges() {
        accessibilityService.$permissionState
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                let granted = state == .granted

                if granted && !self.previousAccessibilityState {
                    // Permission just became available — re-register shortcut
                    Logger.shared.info("Accessibility granted — re-registering shortcut")
                    self.shortcutManager.register()
                } else if !granted && self.previousAccessibilityState {
                    Logger.shared.info("Accessibility revoked")
                }

                self.previousAccessibilityState = granted
            }
            .store(in: &cancellables)
    }

    // MARK: - Restart State Restoration

    private func handleRestartStateRestoration() {
        // Check if we were restarted from settings
        if accessibilityService.consumePendingRestartFromSettings() {
            // Re-check permission after restart
            accessibilityService.recheckPermission()
            // Open popover and navigate to settings
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let button = self?.statusItem?.button else { return }
                self?.showPopover(relativeTo: button)
                NotificationCenter.default.post(
                    name: AppConstants.Notifications.navigateToSettings,
                    object: nil
                )
            }
        }

        // Check if we were restarted from onboarding at the accessibility step
        if let step = accessibilityService.consumePendingRestartOnboardingStep() {
            accessibilityService.recheckPermission()
            Logger.shared.info("Restoring onboarding at step \(step) after restart")
            // The OnboardingManager handles displaying onboarding;
            // the step will be restored via the notification posted below
            NotificationCenter.default.post(
                name: Notification.Name("com.promptcraft.restoreOnboardingStep"),
                object: nil,
                userInfo: ["step": step]
            )
        }
    }

    // MARK: - Deep Link Handler

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "promptcraft"
        else { return }

        Logger.shared.info("Received deep link: \(url.host ?? "")")

        if url.host == "activate" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let key = components?.queryItems?.first(where: { $0.name == "key" })?.value
            let email = components?.queryItems?.first(where: { $0.name == "email" })?.value

            if let key, !key.isEmpty {
                // Post notification for UI listeners (e.g. UpgradeView)
                NotificationCenter.default.post(
                    name: AppConstants.Notifications.deepLinkActivation,
                    object: nil,
                    userInfo: ["key": key, "email": email as Any]
                )

                // Activate the license
                Task {
                    await LicensingService.shared.activateLicense(key: key)
                }
            }
        }
    }

    // MARK: - App Mode

    private func applyAppMode(_ mode: AppMode) {
        let showDock = ConfigurationService.shared.configuration.showDockIcon
        switch mode {
        case .menubarOnly:
            desktopWindowController?.hideWindow()
            NSApp.setActivationPolicy(.accessory)
        case .desktopWindow:
            desktopWindowController?.showWindow()
            NSApp.setActivationPolicy(showDock ? .regular : .accessory)
        case .both:
            desktopWindowController?.showWindow()
            NSApp.setActivationPolicy(showDock ? .regular : .accessory)
        }
    }

    private struct AppModeKey: Equatable {
        let mode: AppMode
        let showDock: Bool
    }

    private func observeAppModeChanges() {
        ConfigurationService.shared.$configuration
            .map { AppModeKey(mode: $0.appMode, showDock: $0.showDockIcon) }
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] key in
                self?.applyAppMode(key.mode)
            }
            .store(in: &cancellables)
    }

    // MARK: - Theme

    private func applyTheme(_ theme: ThemePreference) {
        let appearance = theme.nsAppearance
        NSApp.appearance = appearance
        // Always resolve to explicit appearance for the popover's NSVisualEffectView
        // to avoid rendering differences between system-inherited (nil) and explicit appearances
        let popoverAppearance = appearance ?? Self.resolvedSystemAppearance()
        popover?.contentViewController?.view.appearance = popoverAppearance
        popover?.contentViewController?.view.window?.appearance = popoverAppearance
        desktopWindowController?.window?.appearance = appearance
    }

    private static func resolvedSystemAppearance() -> NSAppearance? {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    private func observeSystemAppearance() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceDidChange),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    @objc private func systemAppearanceDidChange() {
        guard ConfigurationService.shared.configuration.themePreference == .system else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.applyTheme(.system)
        }
    }

    private func observeThemeChanges() {
        ConfigurationService.shared.$configuration
            .map(\.themePreference)
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] theme in self?.applyTheme(theme) }
            .store(in: &cancellables)
    }

    @objc private func handleOpenDesktopWindow() {
        desktopWindowController?.showWindow()
        let config = ConfigurationService.shared.configuration
        if config.appMode == .menubarOnly {
            // Temporarily show without changing saved mode
            let showDock = config.showDockIcon
            NSApp.setActivationPolicy(showDock ? .regular : .accessory)
        }
    }

    // MARK: - Context Menu (Right-Click)

    private func showContextMenu() {
        guard let statusItem else { return }

        // Close popover if open
        popover?.performClose(nil)

        let menu = ContextMenuService.shared.buildMenu(updater: updaterController.updater)

        // Temporarily assign menu to status item so it appears at the correct position
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Remove menu immediately so left-click works normally next time
        statusItem.menu = nil
    }
}
