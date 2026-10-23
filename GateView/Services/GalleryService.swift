import AppKit
import ImageIO

/// Experimental slideshow from a folder. Only the current + next photo are decoded (as ≤900 px thumbnails),
/// and the timer skips while paused (desktop covered, Low Power Mode).
@MainActor
final class GalleryService: ObservableObject {
    @Published private(set) var current: NSImage?
    @Published private(set) var currentURL: URL?
    @Published private(set) var count = 0
    var paused = false

    private var files: [URL] = []
    private var index = 0
    private var next: NSImage?
    private var task: Task<Void, Never>?

    static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp"]

    func start(folder: String, interval: Double) {
        stop()
        let url = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
        files = Self.images(in: url).shuffled()
        count = files.count
        index = 0
        guard !files.isEmpty else { return }
        Task { await show(index) }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(max(interval, 5) * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                if !self.paused && !ProcessInfo.processInfo.isLowPowerModeEnabled { await self.step(1) }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        current = nil
        next = nil
        currentURL = nil
        files = []
        count = 0
    }

    func step(_ delta: Int) async {
        guard !files.isEmpty else { return }
        index = (index + delta + files.count) % files.count
        if delta == 1, let preloaded = next {
            current = preloaded
            currentURL = files[index]
            next = nil
            await preload()
        } else {
            await show(index)
        }
    }

    func revealCurrent() {
        if let currentURL { NSWorkspace.shared.activateFileViewerSelecting([currentURL]) }
    }

    private func show(_ i: Int) async {
        let url = files[i]
        current = await Self.load(url)
        currentURL = url
        await preload()
    }

    private func preload() async {
        guard files.count > 1 else { return }
        let url = files[(index + 1) % files.count]
        next = await Self.load(url)
    }

    nonisolated static func images(in folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return items.filter { extensions.contains($0.pathExtension.lowercased()) }
    }

    /// Decode off the main thread, downsampled: a 24 MP photo costs ~3 MB instead of ~100 MB.
    nonisolated static func load(_ url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 900,
                  ] as CFDictionary)
            else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
    }
}
