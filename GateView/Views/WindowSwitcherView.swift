import SwiftUI

/// DockDoor-inspired Live Window Switcher HUD across all open apps & windows.
/// Shows live thumbnails with instant Focus, Close, Minimize, Maximize, and Quit.
struct WindowSwitcherView: View {
    @ObservedObject var dock: DockWindowService
    let dismiss: () -> Void

    @State private var entries: [SwitcherEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Window Switcher", systemImage: "macwindow.on.rectangle")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if !dock.hasScreenRecording {
                    Button("Enable Live Thumbnails…") { dock.requestScreenRecording() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }

            if entries.isEmpty {
                Text("No open windows found.")
                    .font(.system(size: 13))
                    .opacity(0.65)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(entries) { entry in
                            card(entry)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(18)
        .background(Color(red: 0.05, green: 0.06, blue: 0.10).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 34, y: 14)
        .padding(12)
        .foregroundStyle(.white)
        .tint(ThemeStore.shared.theme.accentColor)
        .environment(\.colorScheme, .dark)
        .onAppear { reload() }
    }

    private func reload() {
        entries = dock.switcherEntries()
        for entry in entries.prefix(12) {
            if let w = entry.window {
                dock.loadPreview(for: w)
            }
        }
    }

    private func card(_ entry: SwitcherEntry) -> some View {
        let app = entry.app
        let win = entry.window
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(nsImage: dock.icon(for: app.pid))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                Text(win?.title ?? app.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let win {
                    Button { dock.minimize(app: app, window: win); reload() } label: {
                        Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                    }.buttonStyle(.plain).help("Minimize")
                    Button { dock.close(app: app, window: win); reload() } label: {
                        Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                    }.buttonStyle(.plain).help("Close")
                }
                Button { dock.quit(app: app); reload() } label: {
                    Image(systemName: "power").font(.system(size: 10, weight: .bold)).foregroundStyle(.red.opacity(0.85))
                }.buttonStyle(.plain).help("Quit \(app.name)")
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.06))
                if let win, let thumb = dock.previews[win.id] {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 220, height: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        Image(nsImage: dock.icon(for: app.pid))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 42, height: 42)
                        Text(app.name)
                            .font(.system(size: 11))
                            .opacity(0.65)
                    }
                }
            }
            .frame(width: 220, height: 130)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(app.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.14)), lineWidth: app.isActive ? 1.5 : 0.75))
            .contentShape(Rectangle())
            .onTapGesture {
                dock.focus(app: app, window: win)
                dismiss()
            }
        }
        .padding(10)
        .frame(width: 240)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
