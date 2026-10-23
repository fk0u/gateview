import SwiftUI

struct GalleryWidget: View {
    let expanded: Bool
    @ObservedObject var gallery: GalleryService
    @Environment(\.gateMotion) private var motion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Gallery", systemImage: "photo.on.rectangle").font(.caption.weight(.semibold)).opacity(0.7)
                Text("EXPERIMENTAL").font(.system(size: 8, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.white.opacity(0.12), in: Capsule()).opacity(0.7)
                Spacer()
                if gallery.count > 0 { Text("\(gallery.count) foto").font(.caption2).opacity(0.5) }
            }
            ZStack {
                if let image = gallery.current {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .id(gallery.currentURL) // new photo → cross-fade
                        .transition(.opacity)
                } else {
                    Text(gallery.count == 0 ? "Tidak ada foto di folder ini.\nPilih folder di Settings → Widgets." : "Memuat…")
                        .font(.caption).multilineTextAlignment(.center).opacity(0.5)
                }
            }
            .frame(height: expanded ? 260 : 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(motion ? .easeInOut(duration: 1.2) : nil, value: gallery.currentURL)

            if expanded {
                HStack {
                    Button { Task { await gallery.step(-1) } } label: { Image(systemName: "chevron.left") }
                    Text(gallery.currentURL?.lastPathComponent ?? "").font(.caption).lineLimit(1).opacity(0.6)
                        .frame(maxWidth: .infinity)
                    Button { Task { await gallery.step(1) } } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.plain)
                Button { gallery.revealCurrent() } label: { Label("Show in Finder", systemImage: "folder") }
                    .buttonStyle(.plain).foregroundStyle(.tint).font(.callout.weight(.medium))
            }
        }
    }
}
