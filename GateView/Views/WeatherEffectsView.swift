import AppKit
import QuartzCore
import SwiftUI

/// Weather layer built on Core Animation: particles and drifts are animated by the system render server (GPU),
/// so GateView itself spends ~0% CPU on them. Hidden (not rendered at all) when inactive.
struct WeatherEffectsView: NSViewRepresentable {
    let code: Int
    let intensity: String   // subtle | full
    let active: Bool

    enum Kind: Equatable { case none, drizzle, rain, storm, fog }

    static func kind(for code: Int) -> Kind {
        switch code {
        case 45, 48: return .fog
        case 51...57: return .drizzle
        case 61...67, 80...82: return .rain
        case 95...99: return .storm
        default: return .none
        }
    }

    func makeNSView(context: Context) -> EffectsHostView { EffectsHostView() }

    func updateNSView(_ view: EffectsHostView, context: Context) {
        let kind = Self.kind(for: code)
        view.configure(kind: kind, full: intensity == "full",
                       active: active && kind != .none && !ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}

final class EffectsHostView: NSView {
    private var kind: WeatherEffectsView.Kind = .none
    private var full = false
    private let container = CALayer()
    private let fade = CAGradientLayer()
    private var builtSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(container)
        // Fade toward the top so it stays ambient, not a screen filter. (Layer y grows upward.)
        fade.colors = [NSColor.black.cgColor, NSColor.black.withAlphaComponent(0.6).cgColor, NSColor.clear.cgColor]
        fade.locations = [0, 0.5, 1]
        container.mask = fade
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil } // never steals clicks

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        fade.frame = bounds
        CATransaction.commit()
        // SwiftUI lays out every second (clock); rebuilding emitters each time was the CPU sink.
        if bounds.size != builtSize { rebuild() }
    }

    func configure(kind: WeatherEffectsView.Kind, full: Bool, active: Bool) {
        container.isHidden = !active
        guard kind != self.kind || full != self.full else { return }
        self.kind = kind
        self.full = full
        rebuild()
    }

    private func rebuild() {
        container.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard bounds.width > 0 else { return }
        builtSize = bounds.size
        let scale: Float = full ? 1.8 : 1
        switch kind {
        case .drizzle: container.addSublayer(rain(rate: 60 * scale, speed: 260, length: 10, alpha: 0.18))
        case .rain: container.addSublayer(rain(rate: 140 * scale, speed: 620, length: 18, alpha: 0.22))
        case .storm:
            container.addSublayer(rain(rate: 220 * scale, speed: 820, length: 22, alpha: 0.26))
            container.addSublayer(flash(peak: 0.08 * Double(scale)))
        case .fog: fog(alpha: 0.10 * CGFloat(scale)).forEach(container.addSublayer)
        case .none: break
        }
    }

    private func rain(rate: Float, speed: CGFloat, length: CGFloat, alpha: CGFloat) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.emitterShape = .line
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.height + length)
        emitter.emitterSize = CGSize(width: bounds.width * 1.2, height: 1)

        let cell = CAEmitterCell()
        cell.contents = Self.dropImage(length: length)
        cell.birthRate = rate
        cell.lifetime = Float((bounds.height + length * 2) / (speed * 0.7))
        cell.velocity = speed
        cell.velocityRange = speed * 0.3
        cell.emissionLongitude = -.pi / 2 - 0.12 // straight down with a light slant
        cell.alphaRange = Float(alpha) * 0.5
        cell.color = NSColor.white.withAlphaComponent(alpha).cgColor
        cell.scale = 0.5 // drop image is drawn @2x
        emitter.emitterCells = [cell]
        emitter.transform = CATransform3DMakeRotation(-0.12, 0, 0, 1)
        return emitter
    }

    private func flash(peak: Double) -> CALayer {
        let layer = CALayer()
        layer.frame = bounds
        layer.backgroundColor = NSColor.white.cgColor
        layer.opacity = 0
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [0, 0, peak, 0]
        anim.keyTimes = [0, 0.955, 0.962, 1]
        anim.duration = 11
        anim.repeatCount = .infinity
        layer.add(anim, forKey: "flash")
        return layer
    }

    private func fog(alpha: CGFloat) -> [CALayer] {
        (0..<3).map { i in
            let s = CGFloat(i)
            let layer = CAGradientLayer()
            layer.type = .radial
            layer.colors = [NSColor.white.withAlphaComponent(alpha).cgColor, NSColor.clear.cgColor]
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 1)
            let w = bounds.width * (0.9 + 0.2 * s)
            layer.bounds = CGRect(x: 0, y: 0, width: w, height: w * 0.35)
            layer.position = CGPoint(x: bounds.width * 0.3, y: bounds.height * (0.35 - 0.12 * s))
            let drift = CABasicAnimation(keyPath: "position.x")
            drift.fromValue = bounds.width * (0.2 + 0.1 * s)
            drift.toValue = bounds.width * (0.8 - 0.1 * s)
            drift.duration = 40 + Double(i) * 15
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(drift, forKey: "drift")
            return layer
        }
    }

    private static func dropImage(length: CGFloat) -> CGImage? {
        let size = CGSize(width: 2, height: length * 2)
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [NSColor.clear.cgColor, NSColor.white.cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
        return ctx.makeImage()
    }
}
