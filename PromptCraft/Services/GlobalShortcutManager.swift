import AppKit
import Combine

final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    /// Called when the global shortcut is triggered.
    var onShortcutActivated: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let configurationService = ConfigurationService.shared
    private let accessibilityService = AccessibilityService.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Re-register when the shortcut configuration changes.
        configurationService.$configuration
            .map(\.globalShortcut)
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reregister()
            }
            .store(in: &cancellables)

        // Re-register when accessibility permission state changes.
        accessibilityService.$permissionState
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                if state == .granted {
                    self?.reregister()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Registration

    func register() {
        accessibilityService.requestAccessibilityIfNeeded()
        installMonitors()
        Logger.shared.info("Global shortcut registered: \(configurationService.configuration.globalShortcut.displayString)")
    }

    func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    // MARK: - Private

    private func reregister() {
        unregister()
        installMonitors()
        Logger.shared.info("Global shortcut re-registered")
    }

    private func installMonitors() {
        let shortcut = configurationService.configuration.globalShortcut

        // Global monitor — fires when PromptCraft is NOT the frontmost app.
        // Requires accessibility permissions.
        if accessibilityService.isAccessibilityGranted {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if shortcut.matches(event) {
                    DispatchQueue.main.async {
                        self?.onShortcutActivated?()
                    }
                }
            }
        }

        // Local monitor — fires when PromptCraft IS the frontmost app.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if shortcut.matches(event) {
                DispatchQueue.main.async {
                    self?.onShortcutActivated?()
                }
                return nil // consume the event
            }
            return event
        }
    }
}
