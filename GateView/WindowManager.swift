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
    /// True while a fullscreen app is in front → the whole overlay fades out (theme.autoHideFullscreen).
    @Published private(set) var overlaySuppressed = false
    @Published private(set) var hovered: String?
    @Published var expanded: String? {
        didSet {
            updateMouse()
            updateKeyFocus()
            layoutNotch()
        }
    }

    var hitRegions: [String: CGRect] = [:] {
        didSet { updateMouse() }
    }

    private var window: DesktopWindow?
    private var notchWindow: DesktopWindow?
    private var dockPreviewWindow: DesktopWindow?
    private var switcherWindow: DesktopWindow?
    private weak var viewModel: DashboardViewModel?
    private var observers: [NSObjectProtocol] = []
    private var monitors: [Any] = []
    private var subscriptions: Set<AnyCancellable> = []
    private let store = ThemeStore.shared
    private var lastDockProbe: TimeInterval = 0
    private var dockHideTask: Task<Void, Never>?
    private var lastCapsLock = NSEvent.modifierFlags.contains(.capsLock)

    func show(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        let window = DesktopWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.hidesOnDeactivate = false // panels hide when their app deactivates by default
        // Become key only for views that need the keyboard (the Notes editor); a plain widget click
        // leaves keyboard focus with the app you were using.
        window.becomesKeyOnlyIfNeeded = true
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

        setupNotchWindow(viewModel: viewModel)
        setupDockPreviewWindow(viewModel: viewModel)
        setupSwitcherWindow(viewModel: viewModel)

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
        store.$theme.map(\.autoHideFullscreen).removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.updateSuppression() }
            .store(in: &subscriptions)
        store.$theme.map(\.showNotch).removeDuplicates()
            .sink { [weak self] _ in self?.layoutNotch() }
            .store(in: &subscriptions)
        store.$theme.map(\.showDock).removeDuplicates()
            .sink { [weak self] on in if !on { self?.hideDockPreview() } }
            .store(in: &subscriptions)

        // Fullscreen apps switch without NSWindow notifications of our own, so watch app activation.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.updateSuppression() }
            })
        }
        updateSuppression()

        // Event-driven hover tracking; mouse monitors need no Accessibility permission.
        let move: (NSEvent) -> Void = { [weak self] _ in
            self?.updateMouse()
            self?.probeRealDock()
        }
        let click: (NSEvent) -> Void = { [weak self] _ in
            guard let self else { return }
            let pt = NSEvent.mouseLocation
            if self.expanded == "notch", let nf = self.notchWindow?.frame, !nf.contains(pt) {
                self.expanded = nil
                return
            }
            if let dp = self.dockPreviewWindow, dp.isVisible, !dp.frame.contains(pt) {
                self.hideDockPreview()
            }
            if let sw = self.switcherWindow, sw.isVisible, !sw.frame.contains(pt) {
                self.hideSwitcher()
            }
            guard self.expanded != nil, self.region(at: pt) == nil else { return }
            self.expanded = nil // click outside closes the detail card
        }
        let flags: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.store.theme.showNotch else { return }
            let caps = event.modifierFlags.contains(.capsLock)
            if caps != self.lastCapsLock {
                self.lastCapsLock = caps
                self.viewModel?.productivity.showToast(
                    symbol: caps ? "capslock.fill" : "capslock",
                    title: caps ? "Caps Lock ON" : "Caps Lock OFF",
                    tintHex: caps ? "#FFC56B" : "#9BA3B4",
                    duration: 1.8
                )
            }
        }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: move),
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: click),
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags),
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseExited]) { move($0); return $0 },
        ].compactMap { $0 }
    }

    /// Typing in Notes needs keyboard focus, which a desktop-level window normally never gets.
    private func updateKeyFocus() {
        guard let window else { return }
        if expanded == "notes" {
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
        let id = overlaySuppressed || clickThrough || !store.theme.interactive ? nil : region(at: NSEvent.mouseLocation)
        if hovered != id { hovered = id }
        if window.ignoresMouseEvents != (id == nil) { window.ignoresMouseEvents = id == nil } // window-server call: only on change
    }

    /// Fade the whole overlay while a fullscreen app owns the screen (a presentation, a game, a fullscreen browser).
    private func updateSuppression() {
        let hidden = store.theme.autoHideFullscreen && Self.frontmostAppIsFullscreen()
        guard hidden != overlaySuppressed else { return }
        overlaySuppressed = hidden
        if let window {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                window.animator().alphaValue = hidden ? 0 : 1
            }
        }
        layoutNotch()
        if hidden { hideDockPreview() }
        updateMouse()
    }

    /// The frontmost app has an on-screen layer-0 window exactly covering a screen → fullscreen.
    static func frontmostAppIsFullscreen(app: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
                                         screens: [NSScreen] = NSScreen.screens) -> Bool {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        for info in list where (info["kCGWindowOwnerPID"] as? NSNumber)?.int32Value == app.processIdentifier {
            guard (info["kCGWindowLayer"] as? NSNumber)?.intValue == 0,
                  let bounds = info["kCGWindowBounds"] as? [String: NSNumber],
                  let width = bounds["Width"]?.doubleValue, let height = bounds["Height"]?.doubleValue
            else { continue }
            if screens.contains(where: { abs(width - $0.frame.width) < 2 && abs(height - $0.frame.height) < 2 }) { return true }
        }
        return false
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
        layoutNotch()
    }

    // MARK: Sticky Top-Edge Notch Panel (always in front of all windows)

    private func setupNotchWindow(viewModel: DashboardViewModel) {
        let panel = DesktopWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 32),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // Above the menu bar and every regular app window — sticky at the very top front.
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = FirstClickHostingView(
            rootView: NotchView(
                viewModel: viewModel,
                nowPlaying: viewModel.nowPlaying,
                stats: viewModel.stats,
                productivity: viewModel.productivity,
                notesStore: .shared,
                reminders: viewModel.remindersService,
                windows: self,
                store: .shared
            )
        )
        notchWindow = panel
        layoutNotch()
    }

    func focusNotchForTyping() {
        guard let panel = notchWindow, panel.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    func layoutNotch() {
        guard let panel = notchWindow else { return }
        guard store.theme.showNotch && !overlaySuppressed else {
            panel.orderOut(nil)
            return
        }
        let screens = NSScreen.screens
        guard let screen = screens.indices.contains(store.theme.displayIndex) ? screens[store.theme.displayIndex] : NSScreen.main else { return }
        let isExpanded = expanded == "notch"
        let width: CGFloat = isExpanded ? 596 : 360
        let height: CGFloat = isExpanded ? 348 : 38
        let frame = NSRect(
            x: round(screen.frame.midX - width / 2),
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        if !isExpanded && panel.isKeyWindow {
            panel.resignKey()
            NSApp.deactivate()
        }
    }

    // MARK: Floating Dock Window Preview Panel (above real macOS Bottom Dock)

    private func setupDockPreviewWindow(viewModel: DashboardViewModel) {
        let panel = DesktopWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 210),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = FirstClickHostingView(
            rootView: DockView(dock: viewModel.dock, nowPlaying: viewModel.nowPlaying, dismiss: { [weak self] in self?.hideDockPreview() })
        )
        dockPreviewWindow = panel
    }

    private func setupSwitcherWindow(viewModel: DashboardViewModel) {
        let panel = DesktopWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 260),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = FirstClickHostingView(
            rootView: WindowSwitcherView(dock: viewModel.dock, dismiss: { [weak self] in self?.hideSwitcher() })
        )
        switcherWindow = panel
    }

    func toggleSwitcher() {
        guard let panel = switcherWindow else { return }
        if panel.isVisible {
            hideSwitcher()
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let width: CGFloat = min(820, screen.frame.width - 80)
        let height: CGFloat = 258
        panel.setFrame(NSRect(
            x: round(screen.frame.midX - width / 2),
            y: round(screen.frame.midY - height / 2),
            width: width,
            height: height
        ), display: true)
        panel.orderFrontRegardless()
    }

    func hideSwitcher() {
        switcherWindow?.orderOut(nil)
    }

    private func probeRealDock() {
        guard store.theme.showDock, !overlaySuppressed, let viewModel else { return }
        let pt = NSEvent.mouseLocation
        // Keep preview open while cursor is inside the preview panel itself.
        if let panel = dockPreviewWindow, panel.isVisible, panel.frame.contains(pt) {
            dockHideTask?.cancel()
            return
        }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastDockProbe >= 0.06 else { return }
        lastDockProbe = now

        if let target = viewModel.dock.dockItem(at: pt) {
            dockHideTask?.cancel()
            if viewModel.dock.hoveredTarget?.app.pid != target.app.pid {
                viewModel.dock.hoveredTarget = target
                for win in target.app.windows.prefix(4) {
                    viewModel.dock.loadPreview(for: win)
                }
            }
            positionDockPreview(for: target)
        } else if dockPreviewWindow?.isVisible == true {
            scheduleHideDockPreview()
        }
    }

    private func positionDockPreview(for target: DockHoveredTarget) {
        guard let panel = dockPreviewWindow else { return }
        let count = max(1, min(target.app.windows.count, 3))
        let hasMedia = ["com.spotify.client", "com.apple.Music"].contains(target.app.bundleID) && viewModel?.nowPlaying.track != nil
        let width: CGFloat = target.app.windows.isEmpty ? 300 : CGFloat(count) * 240 + 36
        let height: CGFloat = (target.app.windows.isEmpty ? 136 : 224) + (hasMedia ? 58 : 0)
        let screen = NSScreen.screens.first { $0.frame.contains(target.iconFrame.origin) } ?? NSScreen.main
        let sf = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = round(target.iconFrame.midX - width / 2)
        x = min(max(x, sf.minX + 12), sf.maxX - width - 12)
        var y = target.iconFrame.maxY + 10
        if y + height > sf.maxY - 40 {
            y = sf.minY + 90
        }
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    private func scheduleHideDockPreview() {
        dockHideTask?.cancel()
        dockHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled, let self else { return }
            let pt = NSEvent.mouseLocation
            if let panel = self.dockPreviewWindow, panel.isVisible, panel.frame.contains(pt) { return }
            if self.viewModel?.dock.dockItem(at: pt) != nil { return }
            self.hideDockPreview()
        }
    }

    func hideDockPreview() {
        dockHideTask?.cancel()
        dockPreviewWindow?.orderOut(nil)
        viewModel?.dock.hoveredTarget = nil
    }
}

/// SwiftUI gestures and buttons only respond in a window that can become key. A non-activating panel can,
/// without activating GateView or stealing focus from the app you're using.
final class DesktopWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// GateView is never the active app; without this the first click on a widget would be eaten by activation.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
