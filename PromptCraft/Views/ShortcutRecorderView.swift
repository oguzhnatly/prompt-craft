import AppKit
import SwiftUI

/// A reusable view for recording and displaying a keyboard shortcut.
/// Shows the current shortcut as a styled badge; click to enter recording mode,
/// then press a new key combination to update the shortcut.
struct ShortcutRecorderView: View {
    @Binding var shortcut: KeyboardShortcutDefinition
    @State private var isRecording = false
    @State private var conflictWarning: String?

    /// System shortcuts that must not be overridden.
    private static let reservedShortcuts: [(String, NSEvent.ModifierFlags)] = [
        ("c", .command),        // Copy
        ("v", .command),        // Paste
        ("x", .command),        // Cut
        ("z", .command),        // Undo
        ("a", .command),        // Select All
        ("q", .command),        // Quit
        ("w", .command),        // Close Window
        ("h", .command),        // Hide
        ("m", .command),        // Minimize
        ("n", .command),        // New
        ("o", .command),        // Open
        ("s", .command),        // Save
        ("p", .command),        // Print
        ("f", .command),        // Find
        (",", .command),        // Preferences
        ("tab", .command),      // App Switcher
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Shortcut badge
                shortcutBadge

                // Reset button
                if shortcut != .default {
                    Button("Reset to Default") {
                        shortcut = .default
                        isRecording = false
                        conflictWarning = nil
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            if let warning = conflictWarning {
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var shortcutBadge: some View {
        Button(action: {
            isRecording.toggle()
            conflictWarning = nil
        }) {
            Text(isRecording ? "Press shortcut..." : shortcut.displayString)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording
                              ? Color.accentColor.opacity(0.15)
                              : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: isRecording ? 1.5 : 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .background(
            ShortcutRecorderKeyListener(isRecording: $isRecording) { event in
                handleKeyEvent(event)
            }
        )
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard isRecording else { return }

        // Ignore bare modifier presses.
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              !chars.isEmpty else { return }

        let targetMods: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let mods = event.modifierFlags.intersection(targetMods)

        // Require at least one modifier.
        guard !mods.isEmpty else {
            conflictWarning = "Shortcut must include at least one modifier key."
            return
        }

        // Check reserved shortcuts.
        for (reservedKey, reservedMods) in Self.reservedShortcuts {
            if chars == reservedKey && mods == reservedMods {
                conflictWarning = "This shortcut conflicts with a system shortcut."
                return
            }
        }

        // Accept the shortcut.
        shortcut = KeyboardShortcutDefinition(
            keyEquivalent: chars,
            commandModifier: mods.contains(.command),
            shiftModifier: mods.contains(.shift),
            optionModifier: mods.contains(.option),
            controlModifier: mods.contains(.control)
        )
        isRecording = false
        conflictWarning = nil
    }
}

// MARK: - NSViewRepresentable Key Listener

/// An invisible NSView that installs a local event monitor to capture key events
/// while the recorder is in recording mode.
private struct ShortcutRecorderKeyListener: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isRecording = isRecording
        context.coordinator.onKeyDown = onKeyDown
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: isRecording, onKeyDown: onKeyDown)
    }

    class Coordinator {
        var isRecording: Bool
        var onKeyDown: (NSEvent) -> Void
        private var monitor: Any?

        init(isRecording: Bool, onKeyDown: @escaping (NSEvent) -> Void) {
            self.isRecording = isRecording
            self.onKeyDown = onKeyDown
        }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isRecording else { return event }
                self.onKeyDown(event)
                return nil // consume event
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
