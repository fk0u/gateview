import SwiftUI

struct NowPlayingDetailView: View {
    let track: NowPlaying
    let service: NowPlayingService
    @State private var scrub: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailHeader(title: "Now Playing", symbol: "music.note")
            HStack(spacing: 14) {
                Group {
                    if let artwork = track.artwork {
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note").font(.largeTitle)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.1))
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.headline).lineLimit(2)
                    Text(track.artist).opacity(0.7).lineLimit(1)
                    if !track.album.isEmpty { Text(track.album).font(.caption).opacity(0.5).lineLimit(1) }
                }
            }
            progress
            HStack(spacing: 28) {
                Spacer()
                control("backward.fill", .previous)
                control(track.isPlaying ? "pause.fill" : "play.fill", .toggle, size: 26)
                control("forward.fill", .next)
                Spacer()
            }
            Button { service.openSource() } label: {
                Label("Buka pemutar", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .font(.callout.weight(.medium))
        }
    }

    // Live only while this card is open and playing; paused timeline costs nothing.
    @MainActor private var progress: some View {
        TimelineView(.periodic(from: .now, by: track.isPlaying && scrub == nil ? 1 : 3600)) { context in // .periodic: no display-link wakeups
            let position = scrub ?? track.position(at: context.date)
            VStack(spacing: 4) {
                if track.duration > 0 {
                    Slider(value: Binding(get: { position }, set: { scrub = $0 }), in: 0...track.duration) { editing in
                        if !editing, let target = scrub {
                            service.seek(to: target)
                            scrub = nil
                        }
                    }
                    .controlSize(.small)
                    HStack {
                        Text(Self.time(position))
                        Spacer()
                        Text("-" + Self.time(track.duration - position))
                    }
                    .font(.caption2.monospacedDigit())
                    .opacity(0.6)
                } else {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right").font(.caption).opacity(0.6)
                }
            }
        }
    }

    static func time(_ seconds: Double) -> String {
        let s = Int(max(seconds, 0))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    @MainActor private func control(_ symbol: String, _ command: NowPlayingService.Command, size: CGFloat = 18) -> some View {
        Button { service.perform(command) } label: {
            Image(systemName: symbol).font(.system(size: size)).frame(width: 40, height: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
