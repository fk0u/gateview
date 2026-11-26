import SwiftUI

/// DockDoor-inspired floating Window Preview panel anchored directly above the hovered
/// icon on the real macOS Bottom Dock. Supports Focus, Minimize/Unminimize, Maximize/Fill,
/// Close, Hide, Quit, and live Media Controls for Spotify/Music.
struct DockView: View {
    @ObservedObject var dock: DockWindowService
    @ObservedObject var nowPlaying: NowPlayingService
    let dismiss: () -> Void

    private static let mediaBundles: Set<String> = ["com.spotify.client", "com.apple.Music"]

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
                    dock.toggleHide(app: app)
                    dismiss()
                } label: {
                    Image(systemName: app.isHidden ? "eye" : "eye.slash")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(app.isHidden ? "Show \(app.name)" : "Hide \(app.name)")

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

            if Self.mediaBundles.contains(app.bundleID), let track = nowPlaying.track {
                mediaControlStrip(track)
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(app.windows.prefix(5)) { win in
                            windowPreviewCard(app: app, win: win)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.05, green: 0.06, blue: 0.09).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
        .padding(6)
    }

    private func mediaControlStrip(_ track: NowPlaying) -> some View {
        HStack(spacing: 10) {
            if let art = track.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                Text(track.artist).font(.system(size: 10)).opacity(0.68).lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(spacing: 10) {
                Button { nowPlaying.perform(.previous) } label: { Image(systemName: "backward.fill") }
                Button { nowPlaying.perform(.toggle) } label: {
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(.tint)
                }
                Button { nowPlaying.perform(.next) } label: { Image(systemName: "forward.fill") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
        }
        .padding(8)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func windowPreviewCard(app: DockAppItem, win: DockAppWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                // macOS traffic-light style window controls: Close, Minimize, Maximize/Fill
                trafficButton(color: Color(red: 1.0, green: 0.37, blue: 0.34), symbol: "xmark", help: "Close window") {
                    dock.close(app: app, window: win)
                    dismiss()
                }
                trafficButton(color: Color(red: 1.0, green: 0.74, blue: 0.18), symbol: "minus", help: win.isMinimized ? "Unminimize" : "Minimize window") {
                    dock.minimize(app: app, window: win)
                    dismiss()
                }
                trafficButton(color: Color(red: 0.16, green: 0.79, blue: 0.25), symbol: "plus", help: "Maximize / Fill screen") {
                    dock.maximize(app: app, window: win)
                    dismiss()
                }

                Text(win.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .padding(.leading, 3)

                Spacer(minLength: 2)

                if win.isMinimized {
                    Text("MIN")
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1.5)
                        .background(.yellow.opacity(0.24), in: Capsule())
                        .foregroundStyle(.yellow)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.06))
                if let thumb = dock.previews[win.id] {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 214, height: 124)
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
            .frame(width: 214, height: 124)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.75))
            .contentShape(Rectangle())
            .onTapGesture {
                dock.focus(app: app, window: win)
                dismiss()
            }
        }
        .padding(8)
        .frame(width: 230)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func trafficButton(color: Color, symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.black.opacity(0.75))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
