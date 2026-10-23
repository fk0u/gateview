import AppKit
import ImageIO

struct NowPlaying: Equatable {
    let title: String
    let artist: String
    let artwork: NSImage?
}

/// Reads the system "Now Playing" via the private MediaRemote framework (event-driven, no polling).
/// ponytail: private API; on macOS 15.4+ Apple limits it to its own apps, so `track` just stays nil there.
@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var track: NowPlaying?

    private typealias GetInfo = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
    private typealias IsPlaying = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias Register = @convention(c) (DispatchQueue) -> Void

    private var getInfo: GetInfo?
    private var isPlaying: IsPlaying?
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard getInfo == nil,
              let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let infoSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo"),
              let playingSym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying"),
              let registerSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")
        else { return }
        getInfo = unsafeBitCast(infoSym, to: GetInfo.self)
        isPlaying = unsafeBitCast(playingSym, to: IsPlaying.self)
        unsafeBitCast(registerSym, to: Register.self)(.main)

        observers = ["kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                     "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"].map {
            NotificationCenter.default.addObserver(forName: Notification.Name($0), object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.refresh() }
            }
        }
        refresh()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        getInfo = nil
        track = nil
    }

    private func refresh() {
        isPlaying?(.main) { [weak self] playing in
            guard let self else { return }
            guard playing else {
                Task { @MainActor in self.track = nil }
                return
            }
            self.getInfo?(.main) { info in
                let title = info?["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                let artist = info?["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                let artwork = (info?["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data).flatMap(Self.thumbnail)
                Task { @MainActor in
                    self.track = title.isEmpty ? nil : NowPlaying(title: title, artist: artist, artwork: artwork)
                }
            }
        }
    }

    /// Downsample artwork so a 3000px cover doesn't cost megabytes of RAM.
    private nonisolated static func thumbnail(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 96,
              ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: 48, height: 48))
    }
}
