import AppKit
import Combine
import SwiftUI

final class InlineOverlayController: ObservableObject {
    static let shared = InlineOverlayController()

    private var panel: NSPanel?
    private let textFieldObserver = TextFieldObserverService.shared
    private let configService = ConfigurationService.shared
    private var cancellables = Set<AnyCancellable>()

    private var showTimer: Timer?
    private var hideTimer: Timer?
    private var dismissed = false
    private var lastFieldPID: pid_t = 0
    private var escapeMonitor: Any?

    @Published var isQuickProcessing = false
    @Published var isOptimizeProcessing = false
    @Published var showSuccess = false

    private init() {
        setupPanel()
        subscribeToFocusChanges()
        setupEscapeMonitor()
    }

    deinit {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        let pillView = InlineOverlayPillView(
            onOptimize: { [weak self] in self?.handleOptimize() },
            onQuick: { [weak self] in self?.handleQuickOptimize() },
            onDismiss: { [weak self] in self?.dismissPill() },
            controller: self
        )

        let hostingView = NSHostingView(rootView: pillView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView

        // Size the panel to fit the pill
        let fittingSize = hostingView.fittingSize
        panel.setContentSize(fittingSize)

        self.panel = panel
    }

    // MARK: - Focus Change Subscription

    private func subscribeToFocusChanges() {
        textFieldObserver.$focusedTextField
            .receive(on: RunLoop.main)
            .sink { [weak self] info in
                self?.handleFocusUpdate(info)
            }
            .store(in: &cancellables)
    }

    private func handleFocusUpdate(_ info: FocusedTextFieldInfo?) {
        // Don't dismiss while processing
        guard !isQuickProcessing && !isOptimizeProcessing else { return }

        guard let info else {
            hidePill()
            return
        }

        let config = configService.configuration

        // Check if overlay is enabled
        guard config.inlineOverlayEnabled else {
            hidePill()
            return
        }

        // Check accessibility
        guard AccessibilityService.shared.isAccessibilityGranted else {
            hidePill()
            return
        }

        // Check excluded apps
        if let bundleID = info.bundleIdentifier,
           config.overlayExcludedApps.contains(bundleID) {
            hidePill()
            return
        }

        // Check minimum text length
        let textLength = info.value?.count ?? 0
        guard textLength >= 10 else {
            hidePill()
            return
        }

        // Reset dismissed flag if different field or app
        if info.pid != lastFieldPID {
            dismissed = false
            lastFieldPID = info.pid
        }

        guard !dismissed else { return }

        // Show after configurable delay
        showTimer?.invalidate()
        let delay = TimeInterval(config.inlineOverlayDelayMs) / 1000.0
        showTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.showPill(for: info)
        }

        // Reset inactivity timer
        resetHideTimer()
    }

    // MARK: - Show / Hide

    private func showPill(for info: FocusedTextFieldInfo) {
        guard let panel else { return }
        guard !dismissed else { return }

        // Calculate position: 4pt below the text field
        let fieldFrame = info.frame
        let pillSize = panel.frame.size

        // Convert from AX screen coordinates (origin at top-left) to AppKit (origin at bottom-left)
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height

        let fieldBottomInAppKit = screenHeight - (fieldFrame.origin.y + fieldFrame.size.height)
        var pillX = fieldFrame.origin.x + (fieldFrame.size.width - pillSize.width) / 2
        var pillY = fieldBottomInAppKit - pillSize.height - 4

        // If pill would go below screen, show above the field
        if pillY < screen.visibleFrame.origin.y {
            let fieldTopInAppKit = screenHeight - fieldFrame.origin.y
            pillY = fieldTopInAppKit + 4
        }

        // Keep pill within horizontal screen bounds
        let maxX = screen.visibleFrame.origin.x + screen.visibleFrame.width - pillSize.width
        let minX = screen.visibleFrame.origin.x
        pillX = min(max(pillX, minX), maxX)

        panel.setFrameOrigin(NSPoint(x: pillX, y: pillY))
        panel.orderFront(nil)
    }

    private func hidePill() {
        showTimer?.invalidate()
        hideTimer?.invalidate()
        panel?.orderOut(nil)
    }

    private func dismissPill() {
        dismissed = true
        hidePill()
    }

    private func resetHideTimer() {
        // Don't auto-hide during processing
        guard !isQuickProcessing && !isOptimizeProcessing else { return }

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.hidePill()
        }
    }

    /// Re-measure the hosting view and resize the panel to fit new content (e.g., text -> spinner).
    private func resizePanelToFit() {
        guard let panel, let hostingView = panel.contentView as? NSHostingView<InlineOverlayPillView> else { return }
        let fittingSize = hostingView.fittingSize
        let origin = panel.frame.origin
        panel.setFrame(NSRect(origin: origin, size: fittingSize), display: true)
    }

    // MARK: - Escape Monitor

    private func setupEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                self?.dismissPill()
            }
            return event
        }
    }

    // MARK: - Actions

    private func handleOptimize() {
        guard let text = textFieldObserver.readValue(), !text.isEmpty else { return }

        isOptimizeProcessing = true
        resizePanelToFit()

        // Brief visual feedback before hiding pill and opening popover
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.isOptimizeProcessing = false
            self.hidePill()

            // Post notification to open popover with this text and auto-optimize flag
            NotificationCenter.default.post(
                name: AppConstants.Notifications.openPopoverWithText,
                object: nil,
                userInfo: ["text": text, "autoOptimize": true]
            )
        }
    }

    private func handleQuickOptimize() {
        guard let text = textFieldObserver.readValue(), !text.isEmpty else { return }

        isQuickProcessing = true
        resizePanelToFit()

        InlineOptimizationService.shared.quickOptimize(text: text) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isQuickProcessing = false

                switch result {
                case .success(let optimized):
                    // Try to write back to the text field
                    if !self.textFieldObserver.writeValue(optimized) {
                        // Fallback: clipboard + simulated Cmd+V
                        ClipboardService.shared.writeText(optimized)
                        self.simulatePaste()
                    }

                    // Show success flash
                    self.showSuccess = true
                    self.resizePanelToFit()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.showSuccess = false
                        self.hidePill()
                    }

                case .failure:
                    // Hide pill on failure — notification is shown by InlineOptimizationService
                    self.hidePill()
                }
            }
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode: CGKeyCode = 9 // V key

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
