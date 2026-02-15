import AppKit
import ApplicationServices
import Combine

struct FocusedTextFieldInfo {
    let element: AXUIElement
    let frame: CGRect
    let pid: pid_t
    let bundleIdentifier: String?
    let value: String?
}

final class TextFieldObserverService: ObservableObject {
    static let shared = TextFieldObserverService()

    @Published private(set) var focusedTextField: FocusedTextFieldInfo?

    private var currentObserver: AXObserver?
    private var currentPID: pid_t = 0
    private var positionPollTimer: Timer?

    private let ownBundleID = Bundle.main.bundleIdentifier ?? AppConstants.bundleIdentifier

    private init() {
        startObserving()
    }

    deinit {
        stopObserving()
    }

    // MARK: - Public API

    /// Read the current text value from the focused text field.
    func readValue() -> String? {
        guard let info = focusedTextField else { return nil }
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(info.element, kAXValueAttribute as CFString, &value)
        guard result == .success, let str = value as? String else { return nil }
        return str
    }

    /// Write a text value to the focused text field.
    @discardableResult
    func writeValue(_ text: String) -> Bool {
        guard let info = focusedTextField else { return false }
        let result = AXUIElementSetAttributeValue(info.element, kAXValueAttribute as CFString, text as CFTypeRef)
        return result == .success
    }

    // MARK: - Observation Setup

    private func startObserving() {
        // Listen for app activation changes
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Initial check for currently focused app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            observeApp(pid: frontApp.processIdentifier, bundleID: frontApp.bundleIdentifier)
        }
    }

    private func stopObserving() {
        positionPollTimer?.invalidate()
        positionPollTimer = nil
        removeCurrentObserver()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func handleAppActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }

        let pid = app.processIdentifier
        let bundleID = app.bundleIdentifier

        // Skip PromptCraft's own windows
        if bundleID == ownBundleID {
            DispatchQueue.main.async { self.focusedTextField = nil }
            return
        }

        observeApp(pid: pid, bundleID: bundleID)
    }

    private func observeApp(pid: pid_t, bundleID: String?) {
        // Skip own app
        if bundleID == ownBundleID { return }

        // Remove previous observer if different app
        if pid != currentPID {
            removeCurrentObserver()
        }

        currentPID = pid
        let appElement = AXUIElementCreateApplication(pid)

        // Create AXObserver for focus changes
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let service = Unmanaged<TextFieldObserverService>.fromOpaque(refcon).takeUnretainedValue()
            service.handleFocusChange(element: element)
        }

        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else {
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        currentObserver = observer

        // Also check the currently focused element immediately
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        if result == .success, let element = focusedElement {
            handleFocusChange(element: element as! AXUIElement)
        }
    }

    private func removeCurrentObserver() {
        if let observer = currentObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        currentObserver = nil
        currentPID = 0
    }

    // MARK: - Focus Change Handler

    private func handleFocusChange(element: AXUIElement) {
        // Check role
        guard let role = axStringAttribute(element, kAXRoleAttribute) else {
            DispatchQueue.main.async { self.focusedTextField = nil }
            return
        }

        let textRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            "AXSearchField",
            kAXComboBoxRole as String,
        ]

        guard textRoles.contains(role) else {
            DispatchQueue.main.async { self.focusedTextField = nil }
            return
        }

        // Skip secure (password) fields
        if let subrole = axStringAttribute(element, kAXSubroleAttribute),
           subrole == (kAXSecureTextFieldSubrole as String) {
            DispatchQueue.main.async { self.focusedTextField = nil }
            return
        }

        // Get position and size
        guard let frame = axFrame(element) else {
            DispatchQueue.main.async { self.focusedTextField = nil }
            return
        }

        // Get current value
        let value = axStringAttribute(element, kAXValueAttribute)

        // Get bundle ID for the owning process
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier

        let info = FocusedTextFieldInfo(
            element: element,
            frame: frame,
            pid: pid,
            bundleIdentifier: bundleID,
            value: value
        )

        DispatchQueue.main.async {
            self.focusedTextField = info
        }

        // Start position polling to track field movement
        startPositionPolling(element: element, pid: pid, bundleID: bundleID)
    }

    // MARK: - Position Polling

    private func startPositionPolling(element: AXUIElement, pid: pid_t, bundleID: String?) {
        positionPollTimer?.invalidate()
        positionPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let frame = self.axFrame(element) else {
                DispatchQueue.main.async { self.focusedTextField = nil }
                self.positionPollTimer?.invalidate()
                return
            }

            let value = self.axStringAttribute(element, kAXValueAttribute)
            let info = FocusedTextFieldInfo(
                element: element,
                frame: frame,
                pid: pid,
                bundleIdentifier: bundleID,
                value: value
            )
            DispatchQueue.main.async {
                self.focusedTextField = info
            }
        }
    }

    // MARK: - AX Helpers

    private func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func axFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: position, size: size)
    }
}
