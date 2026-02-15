import AppKit
import Sparkle
import SwiftUI

final class DesktopWindowController: NSObject, NSWindowDelegate {

    private(set) var window: NSWindow?
    private let viewModel: MainViewModel
    private let updater: SPUUpdater?

    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }

    init(viewModel: MainViewModel, updater: SPUUpdater?) {
        self.viewModel = viewModel
        self.updater = updater
        super.init()
    }

    // MARK: - Window Management

    func showWindow() {
        if window == nil {
            createWindow()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideWindow() {
        window?.orderOut(nil)
    }

    // MARK: - Window Creation

    private func createWindow() {
        let rootView = MainPopoverView(viewModel: viewModel, updater: updater)
            .environment(\.isWindowMode, true)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .sidebar
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow

        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "PromptCraft"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .visible
        win.minSize = NSSize(width: 400, height: 500)
        win.maxSize = NSSize(width: 800, height: 900)
        win.setFrameAutosaveName("PromptCraftDesktopWindow")
        win.isReleasedWhenClosed = false
        win.collectionBehavior.remove(.fullScreenPrimary)
        win.contentView = visualEffect
        win.delegate = self
        win.center()

        win.appearance = ConfigurationService.shared.configuration.themePreference.nsAppearance

        self.window = win
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
