import SwiftUI

/// Hit-test frames of interactive widgets, in the hosting view's top-left coordinate space.
struct HitRegionsKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }

    /// Smallest match wins, so a widget nested in another (weather inside the clock) gets the hover.
    static func hit(_ point: CGPoint, in regions: [String: CGRect]) -> String? {
        regions.filter { $0.value.contains(point) }
            .min { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?.key
    }
}
