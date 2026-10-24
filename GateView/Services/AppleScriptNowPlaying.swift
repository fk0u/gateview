import AppKit

/// MediaRemote is blocked on macOS 15.4+, so there we poll Spotify and Music via AppleScript.
/// Sending Apple events asks for Automation permission once per player; nothing launches
/// because a player is only queried while NSRunningApplication says it is already running.
@MainActor
final class AppleScriptNowPlaying {
    /// Both scripts emit fields joined by ASCII 31 (unit separator, never in tags), one per line.
    private static let sep = "\u{1F}"
    static let players: [(bundleID: String, scriptName: String)] = [
        ("com.spotify.client", "Spotify"),
        ("com.apple.Music", "Music"),
    ]

    var onUpdate: ((NowPlaying?) -> Void)?

    private var pollTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "gateview.applescript", qos: .utility)
    private var currentApp: String?        // bundleID of the player that owns the last reported track
    private var lastKey = ""               // "app|title|artist": only artwork refetches on change
    private var artwork: NSImage?
    private var lastReported: NowPlaying?

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.poll()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        currentApp = nil
        lastReported = nil
        onUpdate?(nil)
    }

    private func poll() {
        let running = Self.players.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }
        guard !running.isEmpty else {
            deliver(nil)
            return
        }
        let script = Self.script(for: running.map(\.scriptName))
        queue.async { [weak self] in
            let output = Self.execute(script)
            Task { @MainActor [weak self] in self?.handle(output) }
        }
    }

    private func handle(_ output: String) {
        guard let entry = Self.pick(output) else { deliver(nil); return }
        let (app, playing, title, artist, album, duration, position, artworkURL) = entry
        currentApp = app
        let key = "\(app)|\(title)|\(artist)"
        if key != lastKey {
            lastKey = key
            artwork = nil
            if let url = artworkURL.flatMap(URL.init(string:)) {
                fetchArtwork(url)
            }
        }
        deliver(NowPlaying(title: title, artist: artist, album: album, artwork: artwork, isPlaying: playing,
                           duration: duration, elapsed: position, timestamp: Date(), rate: playing ? 1 : 0))
    }

    private func deliver(_ track: NowPlaying?) {
        // Keep the object identity stable when nothing changed, so SwiftUI diffing stays cheap.
        if let track, let last = lastReported, track == last { return }
        lastReported = track
        onUpdate?(track)
    }

    private func fetchArtwork(_ url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data else { return }
            Task { @MainActor [weak self] in
                guard let self, let image = NowPlayingService.thumbnail(data) else { return }
                self.artwork = image
                if let last = self.lastReported {
                    self.deliver(NowPlaying(title: last.title, artist: last.artist, album: last.album, artwork: image,
                                            isPlaying: last.isPlaying, duration: last.duration, elapsed: last.elapsed,
                                            timestamp: last.timestamp, rate: last.rate))
                }
            }
        }.resume()
    }

    // MARK: Playback control

    func perform(_ command: NowPlayingService.Command) {
        guard let app = currentApp.flatMap({ id in Self.players.first { $0.bundleID == id }?.scriptName }) else { return }
        let verb: String
        switch command {
        case .toggle: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        queue.async { _ = Self.execute("tell application \"\(app)\" to \(verb)") }
    }

    func seek(to seconds: Double) {
        guard let app = currentApp.flatMap({ id in Self.players.first { $0.bundleID == id }?.scriptName }) else { return }
        queue.async { _ = Self.execute("tell application \"\(app)\" to set player position to \(Int(seconds))") }
        if var track = lastReported {
            track = NowPlaying(title: track.title, artist: track.artist, album: track.album, artwork: track.artwork,
                               isPlaying: track.isPlaying, duration: track.duration, elapsed: seconds,
                               timestamp: Date(), rate: track.rate)
            deliver(track)
        }
    }

    func openSource() {
        guard let id = currentApp, let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { return }
        app.activate(options: [])
    }

    // MARK: Plumbing

    /// One combined script; the running player fills its line. `application X is running` never launches X.
    nonisolated static func script(for apps: [String]) -> String {
        let sep = "character id 31"
        return """
        set sep to \(sep)
        set out to ""
        \(apps.map(body).joined(separator: "\n"))
        return out
        """
    }

    private nonisolated static func body(_ app: String) -> String {
        """
        if application "\(app)" is running then
        \ttell application "\(app)"
        \t\tif player state is not stopped then
        \t\t\ttry
        \t\t\t\tset t to name of current track
        \t\t\t\tset a to artist of current track
        \t\t\t\tset al to album of current track
        \t\t\t\tset d to duration of current track as text
        \t\t\t\tset p to player position as text
        \t\t\t\tset s to (player state is playing) as text
        \t\t\t\tset u to ""
        \(app == "Spotify" ? "\t\t\t\ttry\n\t\t\t\t\tset u to artwork url of current track\n\t\t\t\tend try" : "")
        \t\t\t\tset ln to "\(app)" & sep & s & sep & t & sep & a & sep & al & sep & d & sep & p & sep & u
        \t\t\t\tif out is "" then
        \t\t\t\t\tset out to ln
        \t\t\t\telse
        \t\t\t\t\tset out to out & linefeed & ln
        \t\t\t\tend if
        \t\t\tend try
        \t\tend if
        \tend tell
        end if
        """
    }

    /// Runs on a utility queue; NSAppleScript is created per call (it is not thread-safe to share).
    nonisolated static func execute(_ source: String) -> String {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return result?.stringValue ?? ""
    }

    /// The playing player wins; a paused one still shows its track. Duration: Spotify reports ms, Music seconds.
    nonisolated static func pick(_ output: String) -> (app: String, playing: Bool, title: String, artist: String, album: String,
                                                        duration: Double, position: Double, artworkURL: String?)? {
        let lines = output.split(separator: "\n").map(String.init)
        let entries = lines.compactMap(parseLine)
        return entries.first { $0.playing } ?? entries.first
    }

    nonisolated static func parseLine(_ line: String) -> (app: String, playing: Bool, title: String, artist: String, album: String,
                                                           duration: Double, position: Double, artworkURL: String?)? {
        let f = line.components(separatedBy: sep)
        guard f.count == 8, !f[2].isEmpty else { return nil }
        var duration = Double(f[5]) ?? 0
        if f[0] == "Spotify" { duration /= 1000 }
        return (f[0], f[1] == "true", f[2], f[3], f[4], duration, Double(f[6]) ?? 0, f[7].isEmpty ? nil : f[7])
    }
}
