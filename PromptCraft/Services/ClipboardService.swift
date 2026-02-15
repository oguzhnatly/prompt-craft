import AppKit
import CoreGraphics

final class ClipboardService {
    static let shared = ClipboardService()

    private let pasteboard = NSPasteboard.general

    private init() {}

    // MARK: - Read

    /// Read plain-text content from the system clipboard.
    /// Returns `nil` if the clipboard is empty or contains non-text data (images, files, etc.).
    func readText() -> String? {
        // Only read string type — silently return nil for non-text data (images, files, etc.)
        pasteboard.string(forType: .string)
    }

    /// The current clipboard change count — incremented each time the clipboard changes.
    var changeCount: Int {
        pasteboard.changeCount
    }

    // MARK: - Write

    /// Write text to the system clipboard.
    /// Returns true on success, false on failure.
    @discardableResult
    func writeText(_ text: String) -> Bool {
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        if !success {
            Logger.shared.error("Failed to write text to clipboard")
        }
        return success
    }

    // MARK: - Auto-Capture (Simulated Cmd+C)

    /// Programmatically send Cmd+C to the frontmost application, wait for the clipboard
    /// to update, then return whatever text landed on it. Returns `nil` on failure.
    func captureSelectedText(completion: @escaping (String?) -> Void) {
        let changeCountBefore = pasteboard.changeCount

        sendCommandC()

        // Wait for the clipboard to change (up to 200ms, checking every 20ms).
        var attempts = 0
        let maxAttempts = 10
        let timer = Timer.scheduledTimer(withTimeInterval: 0.020, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            attempts += 1

            if self.pasteboard.changeCount != changeCountBefore {
                timer.invalidate()
                // Only return text — ignore non-text clipboard data
                let text = self.readText()
                completion(text)
                return
            }

            if attempts >= maxAttempts {
                timer.invalidate()
                // Clipboard didn't change — the frontmost app may not support Cmd+C.
                completion(nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - Private

    private func sendCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Key code 8 = 'C'
        let keyCode: CGKeyCode = 8

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            Logger.shared.warning("Could not create CGEvent for Cmd+C simulation")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
