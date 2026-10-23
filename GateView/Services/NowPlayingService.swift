import AppKit
import SwiftUI
import ImageIO

struct NowPlaying: Equatable {
    let title: String
    let artist: String
    let album: String
    let artwork: NSImage?
    let isPlaying: Bool
    var duration: Double = 0     // seconds, 0 when unknown (live streams)
    var elapsed: Double = 0      // at `timestamp`
    var timestamp = Date()
    var rate: Double = 0

    /// Current position: MediaRemote reports elapsed at a timestamp; it advances at `rate` while playing.
    func position(at now: Date) -> Double {
        let p = elapsed + (isPlaying ? now.timeIntervalSince(timestamp) * max(rate, 1) : 0)
        return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
    }
}

/// Reads and controls the system "Now Playing" via the private MediaRemote framework (event-driven, no polling).
/// ponytail: private API; on macOS 15.4+ Apple limits it to its own apps, so `track` just stays nil there.
@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var track: NowPlaying?

    enum Command: UInt32 { case toggle = 2, next = 4, previous = 5 }

    private typealias GetInfo = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
    private typealias IsPlaying = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias GetPID = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    private typealias Register = @convention(c) (DispatchQueue) -> Void
    private typealias Send = @convention(c) (UInt32, NSDictionary?) -> Bool
    private typealias SetElapsed = @convention(c) (Double) -> Void

    private var getInfo: GetInfo?
    private var isPlaying: IsPlaying?
    private var getPID: GetPID?
    private var send: Send?
    private var setElapsed: SetElapsed?
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
        getPID = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID").map { unsafeBitCast($0, to: GetPID.self) }
        send = dlsym(handle, "MRMediaRemoteSendCommand").map { unsafeBitCast($0, to: Send.self) }
        setElapsed = dlsym(handle, "MRMediaRemoteSetElapsedTime").map { unsafeBitCast($0, to: SetElapsed.self) }
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

    func perform(_ command: Command) {
        _ = send?(command.rawValue, nil)
    }

    func seek(to seconds: Double) {
        setElapsed?(seconds)
        if let t = track { track = NowPlaying(title: t.title, artist: t.artist, album: t.album, artwork: t.artwork, isPlaying: t.isPlaying,
                                              duration: t.duration, elapsed: seconds, timestamp: Date(), rate: t.rate) }
    }

    /// Brings the player (Spotify, Music, browser…) to the front.
    func openSource() {
        getPID?(.main) { pid in
            NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        }
    }

    private func refresh() {
        isPlaying?(.main) { [weak self] playing in
            guard let self else { return }
            self.getInfo?(.main) { info in
                let title = info?["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                let artist = info?["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                let album = info?["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
                // Browsers post info changes often; only decode artwork when the song changes.
                let same = self.track.map { $0.title == title && $0.artist == artist && $0.artwork != nil } ?? false
                let artwork = same ? nil : (info?["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data).flatMap(Self.thumbnail)
                let duration = info?["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0
                let elapsed = info?["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
                let timestamp = info?["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date ?? Date()
                let rate = info?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? (playing ? 1 : 0)
                Task { @MainActor in
                    let next = title.isEmpty ? nil
                        : NowPlaying(title: title, artist: artist, album: album, artwork: artwork ?? self.track?.artwork, isPlaying: playing,
                                     duration: duration, elapsed: elapsed, timestamp: timestamp, rate: rate)
                    // Animate here: the slide in/out of the widget follows this change.
                    let animate = ThemeStore.shared.theme.motion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    // Animate only appear/disappear/song change; timing-only updates stay instant.
                    let structural = next?.title != self.track?.title || next?.isPlaying != self.track?.isPlaying
                    withAnimation(animate && structural ? .spring(response: 0.5, dampingFraction: 0.85) : nil) { self.track = next }
                }
            }
        }
    }

    /// Downsample artwork so a 3000px cover doesn't cost megabytes of RAM.
    private nonisolated static func thumbnail(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 240,
              ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: 120, height: 120))
    }
}
