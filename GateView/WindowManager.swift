import AppKit
import SwiftUI

@MainActor
final class WindowManager: ObservableObject {
    @Published var clickThrough = true {
        didSet { window?.ignoresMouseEvents = clickThrough }
    }
    /// Dock height: widgets stay clear of it while the scrim runs behind it.
    @Published private(set) var dockInset: CGFloat = 0

    private var window: NSWindow?
    private var screenObserver: NSObjectProtocol?

    func show(viewModel: DashboardViewModel) {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = clickThrough
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DashboardView(viewModel: viewModel, windows: self, store: .shared))
        self.window = window
        layout()
        window.orderFrontRegardless()

        // Follow resolution / display / Dock changes.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.layout() }
        }
    }

    private func layout() {
        guard let screen = NSScreen.main else { return }
        window?.setFrame(screen.frame, display: true)
        dockInset = screen.visibleFrame.minY - screen.frame.minY
    }
}
