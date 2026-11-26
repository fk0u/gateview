import SwiftUI

/// DockDoor-inspired floating Window Preview panel anchored directly above the hovered
/// icon on the real macOS Bottom Dock. Supports Focus, Minimize, Close, and Quit.
struct DockView: View {
    @ObservedObject var dock: DockWindowService
    let dismiss: () -> Void

    var body: some View {
        Group {
            if let target = dock.hoveredTarget {
                previewContent(for: target.app)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .foregroundStyle(.white)
        .tint(ThemeStore.shared.theme.accentColor)
        .environment(\.colorScheme, .dark)
    }

    private func previewContent(for app: DockAppItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(nsImage: dock.icon(for: app.pid))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !app.windows.isEmpty {
                    Text("\(app.windows.count)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                Spacer()
                Button {
                    dock.quit(app: app)
                    dismiss()
                } label: {
                    Label("Quit", systemImage: "power")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(.red.opacity(0.32), in: Capsule())
                        .overlay(Capsule().strokeBorder(.red.opacity(0.5), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .help("Quit \(app.name)")
            }

            if app.windows.isEmpty {
                HStack(spacing: 12) {
                    Image(nsImage: dock.icon(for: app.pid))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.isHidden ? "App is hidden" : "No visible window")
                            .font(.system(size: 12, weight: .medium))
                        Text("Click to bring \(app.name) to front")
                            .font(.system(size: 10.5))
                            .opacity(0.65)
                    }
                    Spacer()
                }
                .padding(10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                    dock.focus(app: app)
                    dismiss()
                }
            } else {
                HStack(spacing: 10) {
                    ForEach(app.windows.prefix(3)) { win in
                        windowPreviewCard(app: app, win: win)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.05, green: 0.06, blue: 0.09).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
        .padding(6)
    }

    private func windowPreviewCard(app: DockAppItem, win: DockAppWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(win.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    dock.minimize(app: app, window: win)
                    dismiss()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 19, height: 19)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Minimize window")

                Button {
                    dock.close(app: app, window: win)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 19, height: 19)
                        .background(.red.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close window")
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.06))
                if let thumb = dock.previews[win.id] {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 208, height: 122)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        Image(nsImage: dock.icon(for: app.pid))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 38, height: 38)
                        Text("\(Int(win.bounds.width))×\(Int(win.bounds.height))")
                            .font(.system(size: 10))
                            .opacity(0.55)
                            .monospacedDigit()
                    }
                }
            }
            .frame(width: 208, height: 122)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.75))
            .contentShape(Rectangle())
            .onTapGesture {
                dock.focus(app: app, window: win)
                dismiss()
            }
        }
        .padding(8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
