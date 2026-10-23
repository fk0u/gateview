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
        didSet {
            updateMouse()
            updateKeyFocus()
        }
    }

    var hitRegions: [String: CGRect] = [:] {
        didSet { updateMouse() }
    }

    private var window: DesktopWindow?
    private var observers: [NSObjectProtocol] = []
    private var monitors: [Any] = []
    private var subscriptions: Set<AnyCancellable> = []
    private let store = ThemeStore.shared

    func show(viewModel: DashboardViewModel) {
        let window = DesktopWindow(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // One above Finder's desktop-icon window (which covers the whole screen and would swallow clicks),
        // still below every app window. Elsewhere the window stays click-through, so icons keep working.
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.contentView = FirstClickHostingView(rootView: DashboardView(viewModel: viewModel, windows: self, store: .shared))
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

    /// Typing in Notes needs keyboard focus, which a desktop-level window normally never gets.
    private func updateKeyFocus() {
        guard let window else { return }
        let typing = expanded == "notes"
        window.allowsKey = typing
        if typing {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
        } else if window.isKeyWindow {
            window.resignKey()
            NSApp.deactivate() // hand focus back to whatever app was in front
        }
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

/// Borderless windows refuse key status; this one accepts it only while Notes is being edited.
final class DesktopWindow: NSWindow {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
}

/// GateView is never the active app; without this the first click on a widget would be eaten by activation.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
