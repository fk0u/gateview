import AppKit
import SwiftUI

/// Everything a user can customize. Stored as ~/.config/gateview/theme.json (hand-editable, live-reloaded).
struct Theme: Codable, Equatable {
    // Look
    var accent = "#FFC56B"
    var font = "default"          // default | rounded | serif | monospaced
    var clockSize = 168.0
    var clockWeight = "ultraLight" // ultraLight | thin | light | regular | medium | bold
    var showSeconds = true
    var panelSide = "right"       // right | left
    var glassTint = 0.25          // 0…1 black over the blur
    var scrim = 0.45              // 0…1 bottom gradient strength
    var greetingName = ""

    // Widgets
    var showWeather = true
    var showNowPlaying = true
    var showStats = true
    var showAgenda = true

    // Location (prayer times + weather)
    var city = "Samarinda"
    var country = "Indonesia"
    var latitude = -0.5022
    var longitude = 117.1536
    var prayerMethod = 20         // Aladhan method id; 20 = Kemenag RI

    // Minutes from adzan to iqamah
    var iqamah = ["Fajr": 10, "Dhuhr": 10, "Asr": 10, "Maghrib": 7, "Isha": 10]

    /// Decodes a partial file: missing keys keep their defaults, so old/handwritten files never break.
    static func decode(_ data: Data) throws -> Theme {
        var merged = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Theme())) as! [String: Any]
        let user = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        merged.merge(user) { _, new in new }
        return try JSONDecoder().decode(Theme.self, from: JSONSerialization.data(withJSONObject: merged))
    }

    var locationKey: String { "\(city)|\(country)|\(latitude)|\(longitude)|\(prayerMethod)|\(iqamah.sorted { $0.key < $1.key })" }

    var accentColor: Color { Color(hex: accent) ?? .orange }
    var fontDesign: Font.Design {
        switch font {
        case "rounded": return .rounded
        case "serif": return .serif
        case "monospaced": return .monospaced
        default: return .default
        }
    }
    var clockFontWeight: Font.Weight {
        switch clockWeight {
        case "thin": return .thin
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "bold": return .bold
        default: return .ultraLight
        }
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/gateview/theme.json")

    @Published var theme: Theme {
        didSet { if theme != oldValue { save() } }
    }
    @Published private(set) var loadError: String?

    private var watcher: DispatchSourceFileSystemObject?

    private init() {
        theme = (try? Data(contentsOf: Self.url)).flatMap { try? Theme.decode($0) } ?? Theme()
        if !FileManager.default.fileExists(atPath: Self.url.path) { save() }
        watch()
    }

    func reset() { theme = Theme() }

    func reveal() { NSWorkspace.shared.activateFileViewerSelecting([Self.url]) }

    func openInEditor() { NSWorkspace.shared.open(Self.url) }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(theme).write(to: Self.url, options: .atomic)
    }

    private func reload() {
        guard let data = try? Data(contentsOf: Self.url) else { return }
        do {
            let fresh = try Theme.decode(data)
            loadError = nil
            if fresh != theme { theme = fresh }
        } catch {
            loadError = "theme.json tidak valid: \(error.localizedDescription)" // keep last good theme
        }
    }

    /// Editors save atomically (rename), so re-open the file after every event.
    private func watch() {
        watcher?.cancel()
        let fd = open(Self.url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.reload()
                self.watch()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}

extension Color {
    init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var hex: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
