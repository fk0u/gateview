import SwiftUI

private struct MotionKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Theme "motion" AND not Reduce Motion. Every animation in the dashboard checks this.
    var gateMotion: Bool {
        get { self[MotionKey.self] }
        set { self[MotionKey.self] = newValue }
    }
}

extension View {
    /// Digits roll like Apple's clocks (macOS 14+); plain update on 13 or when motion is off.
    @ViewBuilder func rollingDigits(_ value: String, enabled: Bool) -> some View {
        if enabled, #available(macOS 14.0, *) {
            contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.35), value: value)
        } else {
            self
        }
    }

    /// Animation only when motion is on.
    func motion<V: Equatable>(_ animation: Animation, value: V, enabled: Bool) -> some View {
        self.animation(enabled ? animation : nil, value: value)
    }
}
