import SwiftUI

/// Hover highlight + click-to-expand + hit-region reporting for one widget.
struct InteractiveCard<Content: View>: View {
    let id: String
    @ObservedObject var windows: WindowManager
    var plate: CGFloat = 0          // > 0: faint rounded plate on hover (for widgets drawn on the wallpaper)
    var motion = true
    @ViewBuilder let content: (_ expanded: Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let expanded = windows.expanded == id
        let hovered = windows.hovered == id
        content(expanded)
            .padding(plate)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(hovered && plate > 0 ? 0.08 : 0))
            )
            .contentShape(Rectangle())
            .background(GeometryReader { geo in
                Color.clear.preference(key: HitRegionsKey.self, value: [id: geo.frame(in: .global)])
            })
            .padding(-plate)
            .scaleEffect(hovered && !expanded && motion && !reduceMotion ? 1.015 : 1)
            .brightness(hovered && !expanded ? 0.04 : 0)
            .onTapGesture {
                let change = { windows.expanded = expanded ? nil : id }
                if motion && !reduceMotion {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86), change)
                } else {
                    change()
                }
            }
            .animation(.easeOut(duration: 0.18), value: hovered)
    }
}

/// Small shared header for detail cards.
struct DetailHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Image(systemName: "chevron.down").opacity(0.5)
        }
        .font(.caption.weight(.semibold))
        .opacity(0.75)
    }
}
