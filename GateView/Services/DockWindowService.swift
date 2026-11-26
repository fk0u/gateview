import AppKit
import ApplicationServices
import Foundation
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

struct DockAppWindow: Identifiable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let bounds: CGRect
    let isMinimized: Bool
}

struct DockAppItem: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let bundleID: String
    let isActive: Bool
    let isHidden: Bool
    let windows: [DockAppWindow]

    var id: pid_t { pid }
}

struct DockHoveredTarget: Equatable {
    let app: DockAppItem
    /// Screen frame of the hovered macOS Dock icon in AppKit coordinates (origin bottom-left).
    let iconFrame: CGRect
}

struct SwitcherEntry: Identifiable, Equatable {
    let app: DockAppItem
    let window: DockAppWindow?
    var id: String { "\(app.pid)-\(window?.id ?? 0)" }
}

/// Enumerates running macOS apps and their windows (including minimized), detects hovered icons
/// on the real macOS Dock via AXList + AXHitTest, captures live ScreenCaptureKit previews,
/// and supports Focus, Minimize/Unminimize, Maximize/Fill, Close, Hide, and Quit.
@MainActor
final class DockWindowService: ObservableObject {
    @Published private(set) var apps: [DockAppItem] = []
    @Published private(set) var previews: [CGWindowID: NSImage] = [:]
    @Published var hoveredTarget: DockHoveredTarget?
    @Published private(set) var hasAccessibility = AXIsProcessTrusted()
    @Published private(set) var hasScreenRecording = CGPreflightScreenCaptureAccess()

    private var observers: [NSObjectProtocol] = []
    private var iconCache: [pid_t: NSImage] = [:]
    private var previewOrder: [CGWindowID] = []
    private let maxCachedPreviews = 24
    private var dockPID: pid_t?
    private var permissionTask: Task<Void, Never>?

    func start() {
        guard observers.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        observers = names.map { name in
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        }
        // Lightweight permission check every 3 s while either permission is missing so enabling
        // it in System Settings takes effect immediately without restarting GateView.
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refreshPermissions()
                if self.hasAccessibility && self.hasScreenRecording { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        refresh()
    }

    func stop() {
        permissionTask?.cancel()
        permissionTask = nil
        let nc = NSWorkspace.shared.notificationCenter
        observers.forEach(nc.removeObserver)
        observers = []
        apps = []
        hoveredTarget = nil
        previews = [:]
        previewOrder = []
        iconCache = [:]
        dockPID = nil
    }

    func refreshPermissions() {
        let ax = AXIsProcessTrusted()
        let sc = CGPreflightScreenCaptureAccess()
        if ax != hasAccessibility { hasAccessibility = ax }
        if sc != hasScreenRecording { hasScreenRecording = sc }
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshPermissions()
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        refreshPermissions()
    }

    func icon(for pid: pid_t) -> NSImage {
        if let cached = iconCache[pid] { return cached }
        let img = NSRunningApplication(processIdentifier: pid)?.icon ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
        iconCache[pid] = img
        return img
    }

    func refresh() {
        let myBundle = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != myBundle && !$0.isTerminated
        }
        let windowsByPID = Self.snapshotWindows()
        let activePIDs = Set(running.map(\.processIdentifier))
        iconCache = iconCache.filter { activePIDs.contains($0.key) }

        apps = running.map { app in
            let pid = app.processIdentifier
            return DockAppItem(
                pid: pid,
                name: app.localizedName ?? "App",
                bundleID: app.bundleIdentifier ?? "",
                isActive: app.isActive,
                isHidden: app.isHidden,
                windows: windowsByPID[pid] ?? []
            )
        }
    }

    /// Flat list of open windows across all running apps for the Option+Tab Window Switcher.
    func switcherEntries() -> [SwitcherEntry] {
        refresh()
        var out: [SwitcherEntry] = []
        let sorted = apps.sorted { a, b in
            if a.isActive != b.isActive { return a.isActive }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        for app in sorted {
            if app.windows.isEmpty {
                out.append(SwitcherEntry(app: app, window: nil))
            } else {
                for w in app.windows.prefix(4) {
                    out.append(SwitcherEntry(app: app, window: w))
                }
            }
        }
        return out
    }

    /// Reads the real macOS Dock's AXList children directly (far more reliable than AXHitTest alone
    /// with Dock magnification and multi-monitor setups) to find the hovered running app icon.
    func dockItem(at screenPoint: NSPoint) -> DockHoveredTarget? {
        guard AXIsProcessTrusted() else { return nil }
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let nearEdge = NSScreen.screens.contains { s in
            let f = s.frame
            let margin: CGFloat = 128
            return f.contains(screenPoint) && (
                screenPoint.y <= f.minY + margin ||
                screenPoint.x <= f.minX + margin ||
                screenPoint.x >= f.maxX - margin
            )
        }
        guard nearEdge else { return nil }

        if dockPID == nil || NSRunningApplication(processIdentifier: dockPID!) == nil {
            dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        }
        guard let pid = dockPID else { return nil }

        let dockEl = AXUIElementCreateApplication(pid)
        let cgPoint = CGPoint(x: screenPoint.x, y: primaryHeight - screenPoint.y)

        // Strategy 1: Enumerate Dock AXList children directly and test their icon rects.
        if let matched = findDockItemInList(dockEl: dockEl, cgPoint: cgPoint, primaryHeight: primaryHeight) {
            return matched
        }

        // Strategy 2: Fallback to AXUIElementCopyElementAtPosition.
        var hitRef: AXUIElement?
        if AXUIElementCopyElementAtPosition(dockEl, Float(cgPoint.x), Float(cgPoint.y), &hitRef) == .success,
           let el = hitRef {
            return resolveDockElement(el, primaryHeight: primaryHeight)
        }
        return nil
    }

    private func findDockItemInList(dockEl: AXUIElement, cgPoint: CGPoint, primaryHeight: CGFloat) -> DockHoveredTarget? {
        var topChildrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockEl, kAXChildrenAttribute as CFString, &topChildrenRef) == .success,
              let topChildren = topChildrenRef as? [AXUIElement]
        else { return nil }

        for child in topChildren {
            var roleRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            guard (roleRef as? String) == (kAXListRole as String) else { continue }

            var itemsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &itemsRef) == .success,
                  let items = itemsRef as? [AXUIElement]
            else { continue }

            for item in items {
                guard let rect = axCGFrame(of: item) else { continue }
                // Slight vertical pad makes hovering magnified Dock icons rock-solid.
                if rect.insetBy(dx: -3, dy: -12).contains(cgPoint) {
                    if let target = resolveDockElement(item, primaryHeight: primaryHeight, knownCGRect: rect) {
                        return target
                    }
                }
            }
        }
        return nil
    }

    private func resolveDockElement(_ el: AXUIElement, primaryHeight: CGFloat, knownCGRect: CGRect? = nil) -> DockHoveredTarget? {
        var subroleRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = subroleRef as? String ?? ""
        guard subrole == "AXApplicationDockItem" || subrole == "AXMinimizedWindowDockItem" else { return nil }

        var titleRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? ""

        var urlRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(el, kAXURLAttribute as CFString, &urlRef)
        let itemURL = urlRef as? URL

        let cgRect = knownCGRect ?? axCGFrame(of: el) ?? CGRect(x: 0, y: primaryHeight - 64, width: 56, height: 56)
        let appKitFrame = CGRect(x: cgRect.origin.x, y: primaryHeight - cgRect.origin.y - cgRect.height, width: cgRect.width, height: cgRect.height)

        let running = NSWorkspace.shared.runningApplications.first { app in
            guard app.activationPolicy == .regular, !app.isTerminated else { return false }
            if let itemURL, let appURL = app.bundleURL, appURL.standardizedFileURL == itemURL.standardizedFileURL {
                return true
            }
            if !title.isEmpty && app.localizedName?.caseInsensitiveCompare(title) == .orderedSame {
                return true
            }
            return title == "Finder" && app.bundleIdentifier == "com.apple.finder"
        }
        guard let running else { return nil }

        let windowsByPID = Self.snapshotWindows()
        let appItem = DockAppItem(
            pid: running.processIdentifier,
            name: running.localizedName ?? title,
            bundleID: running.bundleIdentifier ?? "",
            isActive: running.isActive,
            isHidden: running.isHidden,
            windows: windowsByPID[running.processIdentifier] ?? []
        )
        return DockHoveredTarget(app: appItem, iconFrame: appKitFrame)
    }

    private func axCGFrame(of el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let pVal = posRef, let sVal = sizeRef
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(pVal as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sVal as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0
        else { return nil }
        return CGRect(origin: pos, size: size)
    }

    /// Captures all layer-0 application windows (including minimized/off-space windows).
    nonisolated static func snapshotWindows() -> [pid_t: [DockAppWindow]] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var grouped: [pid_t: [DockAppWindow]] = [:]
        for info in list {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let num = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 80, bounds.height >= 50
            else { continue }
            let onScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            let rawTitle = (info[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Off-screen windows without a title are usually hidden helper surfaces; skip them.
            if !onScreen && rawTitle.isEmpty { continue }
            let owner = (info[kCGWindowOwnerName as String] as? String) ?? "Window"
            let title = rawTitle.isEmpty ? owner : rawTitle
            grouped[pid, default: []].append(DockAppWindow(id: num, pid: pid, title: title, bounds: bounds, isMinimized: !onScreen))
        }
        return grouped
    }

    // MARK: Live Window Preview

    /// Captures a downscaled live preview for `window` on macOS 14+ when Screen Recording is already granted.
    func loadPreview(for window: DockAppWindow) {
        guard CGPreflightScreenCaptureAccess() else { return }
        #if canImport(ScreenCaptureKit)
        if #available(macOS 14.0, *) {
            let wid = window.id
            let target = Self.aspectFit(size: window.bounds.size, maxSize: CGSize(width: 360, height: 220))
            Task { [weak self] in
                guard let image = await Self.captureSCWindow(id: wid, size: target) else { return }
                await MainActor.run {
                    self?.storePreview(image, for: wid)
                }
            }
        }
        #endif
    }

    private func storePreview(_ image: NSImage, for id: CGWindowID) {
        previews[id] = image
        previewOrder.removeAll { $0 == id }
        previewOrder.append(id)
        while previewOrder.count > maxCachedPreviews {
            let evicted = previewOrder.removeFirst()
            previews.removeValue(forKey: evicted)
        }
    }

    #if canImport(ScreenCaptureKit)
    @available(macOS 14.0, *)
    private nonisolated static func captureSCWindow(id: CGWindowID, size: CGSize) async -> NSImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false),
              let scWin = content.windows.first(where: { $0.windowID == id })
        else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: scWin)
        let cfg = SCStreamConfiguration()
        cfg.width = max(1, Int(size.width.rounded()))
        cfg.height = max(1, Int(size.height.rounded()))
        cfg.showsCursor = false
        guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else {
            return nil
        }
        return NSImage(cgImage: cg, size: size)
    }
    #endif

    // MARK: Window Actions (Focus, Minimize, Maximize/Fill, Close, Hide, Quit)

    func focus(app: DockAppItem, window: DockAppWindow? = nil) {
        guard let running = NSRunningApplication(processIdentifier: app.pid) else { return }
        if running.isHidden { running.unhide() }
        running.activate(options: [])
        if let window, let axWin = axWindow(for: window) {
            AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
        }
        refresh()
    }

    func minimize(app: DockAppItem, window: DockAppWindow? = nil) {
        if let window, let axWin = axWindow(for: window) {
            let nextState: CFBoolean = window.isMinimized ? kCFBooleanFalse : kCFBooleanTrue
            if AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, nextState) == .success {
                if window.isMinimized {
                    NSRunningApplication(processIdentifier: app.pid)?.activate(options: [])
                    AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
                }
                refresh()
                return
            }
        }
        NSRunningApplication(processIdentifier: app.pid)?.hide()
        refresh()
    }

    /// Expands the window to fill the visible screen area (green traffic-light action).
    func maximize(app: DockAppItem, window: DockAppWindow) {
        guard let axWin = axWindow(for: window),
              let primaryHeight = NSScreen.screens.first?.frame.height,
              let screen = NSScreen.main ?? NSScreen.screens.first
        else {
            focus(app: app, window: window)
            return
        }
        let vf = screen.visibleFrame
        var pos = CGPoint(x: vf.minX, y: primaryHeight - vf.maxY)
        var size = CGSize(width: vf.width, height: vf.height)
        AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        if let pVal = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, pVal)
        }
        if let sVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, sVal)
        }
        NSRunningApplication(processIdentifier: app.pid)?.activate(options: [])
        AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
        refresh()
    }

    func close(app: DockAppItem, window: DockAppWindow) {
        guard let axWin = axWindow(for: window) else { return }
        var closeButtonRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWin, kAXCloseButtonAttribute as CFString, &closeButtonRef) == .success,
           let closeButton = closeButtonRef {
            AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.refresh()
            }
        }
    }

    func toggleHide(app: DockAppItem) {
        guard let running = NSRunningApplication(processIdentifier: app.pid) else { return }
        if running.isHidden { running.unhide() } else { running.hide() }
        refresh()
    }

    func quit(app: DockAppItem) {
        NSRunningApplication(processIdentifier: app.pid)?.terminate()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.refresh()
        }
    }

    private func axWindow(for window: DockAppWindow) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let appEl = AXUIElementCreateApplication(window.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement], !list.isEmpty
        else { return nil }
        for el in list {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String, title == window.title {
                return el
            }
        }
        return list.first
    }

    nonisolated static func aspectFit(size: CGSize, maxSize: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, maxSize.width > 0, maxSize.height > 0 else {
            return CGSize(width: 240, height: 150)
        }
        let scale = min(maxSize.width / size.width, maxSize.height / size.height, 1.0)
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }
}
