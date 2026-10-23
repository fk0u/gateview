import AppKit
import Combine
import SwiftUI

@MainActor
final class WindowManager: ObservableObject {
    /// Forces the old behaviour: every click goes to the desktop.
    @Published var clickThrough = false {
        didSet { updateMouse() }
    }
    /// Dock height: widgets stay clear of it while the scrim runs behind it.
    @Published private(set) var dockInset: CGFloat = 0
    /// False while the desktop is fully covered by windows → effects pause.
    @Published private(set) var isVisible = true
    @Published private(set) var hovered: String?
    @Published var expanded: String? {
        didSet { updateMouse() }
    }

    var hitRegions: [String: CGRect] = [:] {
        didSet { updateMouse() }
    }

    private var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var monitors: [Any] = []
    private var subscriptions: Set<AnyCancellable> = []
    private let store = ThemeStore.shared

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
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DashboardView(viewModel: viewModel, windows: self, store: .shared))
        self.window = window
        layout()
        window.orderFrontRegardless()

        let center = NotificationCenter.default
        observers = [
            // Follow resolution / display / Dock changes.
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.layout() }
            },
            center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.isVisible = self.window?.occlusionState.contains(.visible) ?? true }
            },
        ]
        store.$theme.map(\.displayIndex).removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.layout() }
            .store(in: &subscriptions)
        store.$theme.map(\.interactive).removeDuplicates()
            .sink { [weak self] _ in self?.updateMouse() }
            .store(in: &subscriptions)

        // Event-driven hover tracking; mouse monitors need no Accessibility permission.
        let move: (NSEvent) -> Void = { [weak self] _ in self?.updateMouse() }
        let click: (NSEvent) -> Void = { [weak self] _ in
            guard let self, self.expanded != nil, self.region(at: NSEvent.mouseLocation) == nil else { return }
            self.expanded = nil // click outside closes the detail card
        }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: move),
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: click),
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseExited]) { move($0); return $0 },
        ].compactMap { $0 }
    }

    /// Only the widget under the cursor captures the mouse; the rest of the desktop stays clickable.
    private func updateMouse() {
        guard let window else { return }
        let id = clickThrough || !store.theme.interactive ? nil : region(at: NSEvent.mouseLocation)
        if hovered != id { hovered = id }
        if window.ignoresMouseEvents != (id == nil) { window.ignoresMouseEvents = id == nil } // window-server call: only on change
    }

    private func region(at screenPoint: NSPoint) -> String? {
        guard let frame = window?.frame else { return nil }
        let p = CGPoint(x: screenPoint.x - frame.minX, y: frame.maxY - screenPoint.y)
        return HitRegionsKey.hit(p, in: hitRegions)
    }

    private func layout() {
        let screens = NSScreen.screens
        guard let screen = screens.indices.contains(store.theme.displayIndex) ? screens[store.theme.displayIndex] : NSScreen.main
        else { return }
        window?.setFrame(screen.frame, display: true)
        dockInset = screen.visibleFrame.minY - screen.frame.minY
    }
}
