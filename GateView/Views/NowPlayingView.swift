import SwiftUI

struct NowPlayingView: View {
    let track: NowPlaying

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let artwork = track.artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").font(.title3).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white.opacity(0.1))
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.body.weight(.medium)).lineLimit(1)
                Text(track.artist).font(.caption).opacity(0.6).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "waveform").foregroundStyle(.tint)
        }
    }
}
