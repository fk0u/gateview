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

/// Enumerates running macOS apps and their windows, detects hovered icons on the real macOS Dock,
/// captures optional live previews, and supports Focus, Minimize, Close, and Quit directly from the preview.
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
    private let maxCachedPreviews = 16
    private var dockPID: pid_t?

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
        refresh()
    }

    func stop() {
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
        hasAccessibility = AXIsProcessTrusted()
        hasScreenRecording = CGPreflightScreenCaptureAccess()
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        refreshPermissions()
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        refreshPermissions()
    }

    /// Queries the real macOS Dock via Accessibility at `screenPoint` (AppKit bottom-left coordinates)
    /// to find the hovered Dock icon and its matching running app.
    func dockItem(at screenPoint: NSPoint) -> DockHoveredTarget? {
        guard AXIsProcessTrusted() else { return nil }
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        // Quick reject: only query AX when cursor is near a screen edge where the Dock can live.
        let nearEdge = NSScreen.screens.contains { s in
            let f = s.frame
            let margin: CGFloat = 110
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

        let cgPoint = CGPoint(x: screenPoint.x, y: primaryHeight - screenPoint.y)
        let dockEl = AXUIElementCreateApplication(pid)
        var hitRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dockEl, Float(cgPoint.x), Float(cgPoint.y), &hitRef) == .success,
              let el = hitRef
        else { return nil }

        var subroleRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = subroleRef as? String ?? ""
        guard subrole == "AXApplicationDockItem" else { return nil }

        var titleRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? ""

        var urlRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(el, kAXURLAttribute as CFString, &urlRef)
        let itemURL = urlRef as? URL

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var pos = CGPoint.zero
        var size = CGSize(width: 56, height: 56)
        if AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
           let pVal = posRef {
            AXValueGetValue(pVal as! AXValue, .cgPoint, &pos)
        }
        if AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sVal = sizeRef {
            AXValueGetValue(sVal as! AXValue, .cgSize, &size)
        }
        let appKitFrame = CGRect(x: pos.x, y: primaryHeight - pos.y - size.height, width: size.width, height: size.height)

        // Match against running regular apps by bundle URL first, then localized name.
        let running = NSWorkspace.shared.runningApplications.first { app in
            guard app.activationPolicy == .regular, !app.isTerminated else { return false }
            if let itemURL, let appURL = app.bundleURL, appURL.standardizedFileURL == itemURL.standardizedFileURL {
                return true
            }
            return !title.isEmpty && app.localizedName == title
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
            let wins = windowsByPID[pid] ?? []
            return DockAppItem(
                pid: pid,
                name: app.localizedName ?? "App",
                bundleID: app.bundleIdentifier ?? "",
                isActive: app.isActive,
                isHidden: app.isHidden,
                windows: wins
            )
        }
    }

    nonisolated static func snapshotWindows() -> [pid_t: [DockAppWindow]] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var grouped: [pid_t: [DockAppWindow]] = [:]
        for info in list {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let num = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 60, bounds.height >= 40
            else { continue }
            let rawTitle = (info[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let owner = (info[kCGWindowOwnerName as String] as? String) ?? "Window"
            let title = rawTitle.isEmpty ? owner : rawTitle
            grouped[pid, default: []].append(DockAppWindow(id: num, pid: pid, title: title, bounds: bounds))
        }
        return grouped
    }

    // MARK: Live Window Preview

    /// Captures a downscaled live preview for `window` on macOS 14+ when Screen Recording is already granted.
    /// Never triggers an unexpected permission popup; UI falls back gracefully to app icon + title.
    func loadPreview(for window: DockAppWindow) {
        guard CGPreflightScreenCaptureAccess() else { return }
        #if canImport(ScreenCaptureKit)
        if #available(macOS 14.0, *) {
            let wid = window.id
            let target = Self.aspectFit(size: window.bounds.size, maxSize: CGSize(width: 320, height: 200))
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

    // MARK: Window Actions (Focus, Minimize, Close, Quit)

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
            let err = AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            if err == .success {
                refresh()
                return
            }
        }
        // Fallback when Accessibility permission isn't granted: hide the app cleanly.
        NSRunningApplication(processIdentifier: app.pid)?.hide()
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
