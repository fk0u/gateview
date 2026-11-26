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

/// Enumerates running macOS apps and their windows, captures optional live previews,
/// and supports Focus, Minimize, Close, and Quit directly from the Dock preview.
@MainActor
final class DockWindowService: ObservableObject {
    @Published private(set) var apps: [DockAppItem] = []
    @Published private(set) var previews: [CGWindowID: NSImage] = [:]

    private var observers: [NSObjectProtocol] = []
    private var iconCache: [pid_t: NSImage] = [:]
    private var previewOrder: [CGWindowID] = []
    private let maxCachedPreviews = 16

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
        previews = [:]
        previewOrder = []
        iconCache = [:]
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
