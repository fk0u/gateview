import AppKit
import ImageIO

/// Derives an accent colour from the current wallpaper. Decodes only when the wallpaper URL changes.
@MainActor
final class WallpaperColorService {
    private let onChange: (NSColor?) -> Void
    private var lastURL: URL?
    private var observers: [NSObjectProtocol] = []
    private var task: Task<Void, Never>?

    init(onChange: @escaping (NSColor?) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard task == nil else { return }
        lastURL = nil
        let refresh: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.check() }
        }
        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: refresh),
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: refresh),
        ]
        // No public "wallpaper changed" notification; a URL compare every 5 min is effectively free.
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.check()
                try? await Task.sleep(nanoseconds: 300_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
        observers = []
    }

    private func check() {
        let screens = NSScreen.screens
        let index = ThemeStore.shared.theme.displayIndex
        guard let screen = screens.indices.contains(index) ? screens[index] : NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen), url != lastURL else { return }
        lastURL = url
        onChange(Self.accent(from: url))
    }

    nonisolated static func accent(from url: URL) -> NSColor? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 32,
              ] as CFDictionary)
        else { return nil }

        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = stride(from: 0, to: data.count, by: 4).map {
            (Double(data[$0]) / 255, Double(data[$0 + 1]) / 255, Double(data[$0 + 2]) / 255)
        }
        return dominant(pixels).map { NSColor(hue: $0.h, saturation: $0.s, brightness: $0.b, alpha: 1) }
    }

    /// Saturation-weighted hue buckets → the most "colourful" hue, lifted to stay readable on dark glass.
    nonisolated static func dominant(_ pixels: [(Double, Double, Double)]) -> (h: Double, s: Double, b: Double)? {
        var weight = [Double](repeating: 0, count: 12)
        var sumS = [Double](repeating: 0, count: 12), sumH = [Double](repeating: 0, count: 12)
        for (r, g, b) in pixels {
            let color = NSColor(red: r, green: g, blue: b, alpha: 1)
            let (hue, sat, bri) = (color.hueComponent, color.saturationComponent, color.brightnessComponent)
            guard sat > 0.2, bri > 0.2 else { continue } // skip greys, blacks, whites
            let i = min(Int(hue * 12), 11)
            let w = sat * bri
            weight[i] += w
            sumS[i] += sat * w
            sumH[i] += hue * w
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0 else { return nil }
        let hue = sumH[best] / weight[best]
        let sat = sumS[best] / weight[best]
        return (hue, min(max(sat, 0.45), 0.8), 0.95)
    }
}
