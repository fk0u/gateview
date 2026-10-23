import SwiftUI

/// Stateless particle layer: every drop's position is a pure function of (index, time), so no per-frame allocation.
/// The TimelineView is paused (0% CPU) when there is no effect, the desktop is covered, or Low Power Mode is on.
struct WeatherEffectsView: View {
    let code: Int
    let intensity: String   // subtle | full
    let active: Bool

    enum Kind { case none, drizzle, rain, storm, fog }

    static func kind(for code: Int) -> Kind {
        switch code {
        case 45, 48: return .fog
        case 51...57: return .drizzle
        case 61...67, 80...82: return .rain
        case 95...99: return .storm
        default: return .none
        }
    }

    var body: some View {
        let kind = Self.kind(for: code)
        let running = active && kind != .none && !ProcessInfo.processInfo.isLowPowerModeEnabled
        if kind != .none {
            TimelineView(.animation(minimumInterval: kind == .fog ? 1.0 / 15 : 1.0 / 30, paused: !running)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    switch kind {
                    case .fog: drawFog(ctx, size, t)
                    case .drizzle: drawRain(ctx, size, t, count: 70, length: 10, speed: 260, opacity: 0.18)
                    case .rain: drawRain(ctx, size, t, count: 140, length: 18, speed: 620, opacity: 0.22)
                    case .storm:
                        drawRain(ctx, size, t, count: 200, length: 22, speed: 820, opacity: 0.26)
                        drawFlash(ctx, size, t)
                    case .none: break
                    }
                }
            }
            // Fade toward the top so the effect stays ambient, not a screen filter.
            .mask(LinearGradient(colors: [.clear, .black.opacity(0.6), .black], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private var scale: Double { intensity == "full" ? 1.8 : 1 }

    private func drawRain(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double, count: Int, length: Double, speed: Double, opacity: Double) {
        let n = Int(Double(count) * scale)
        let slant = 0.18
        var path = Path()
        for i in 0..<n {
            let seed = Double(i)
            let r1 = fract(sin(seed * 12.9898) * 43758.5453)
            let r2 = fract(sin(seed * 78.233) * 12345.6789)
            let v = speed * (0.7 + 0.6 * r2)
            let span = size.height + length
            let y = (t * v + r1 * span).truncatingRemainder(dividingBy: span) - length
            let x = (r1 * (size.width + 200) - 100 + y * slant).truncatingRemainder(dividingBy: size.width + 200)
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + length * slant, y: y + length * (0.8 + 0.4 * r2)))
        }
        ctx.stroke(path, with: .color(.white.opacity(opacity)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
    }

    private func drawFlash(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        // A soft flash roughly every 11 s, fading over ~0.5 s.
        let phase = t.truncatingRemainder(dividingBy: 11)
        guard phase < 0.5 else { return }
        let alpha = (phase < 0.08 ? phase / 0.08 : 1 - (phase - 0.08) / 0.42) * 0.08 * scale
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(alpha)))
    }

    private func drawFog(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        for i in 0..<3 {
            let s = Double(i)
            let x = (sin(t / (40 + s * 15) + s * 2) * 0.5 + 0.5) * size.width
            let y = size.height * (0.55 + 0.15 * s)
            let r = size.width * (0.45 + 0.1 * s)
            let rect = CGRect(x: x - r, y: y - r * 0.35, width: r * 2, height: r * 0.7)
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [.white.opacity(0.10 * scale), .clear]),
                center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: r))
        }
    }

    private func fract(_ x: Double) -> Double { x - x.rounded(.down) }
}
