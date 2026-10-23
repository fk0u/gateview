import AppKit
import UniformTypeIdentifiers
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
    var menuBarScrim = 0.4        // 0…1 dark fade behind the (translucent) system menu bar
    var greetingName = ""

    // Widgets
    var showWeather = true
    var showNowPlaying = true
    var showStats = true
    var showAgenda = true
    var widgetOrder = ["prayer", "agenda", "nowPlaying"] // right-panel order
    var interactive = true        // hover + click widgets for details
    var displayIndex = 0          // 0 = main screen

    // Motion & mood
    var accentMode = "custom"     // custom | wallpaper
    var motion = true
    var mood = true               // tint follows time of day / prayer
    var weatherEffects = "subtle" // off | subtle | full

    // Reminder
    var reminderMode = "off"      // off | banner | chime
    var reminderSound = "Glass"
    var reminders = ["Fajr": true, "Dhuhr": true, "Asr": true, "Maghrib": true, "Isha": true]
    var temperatureUnit = "celsius" // celsius | fahrenheit

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

    /// One-tap looks. Only touch appearance keys; location, widgets and reminders stay.
    static let presets: [(name: String, apply: (inout Theme) -> Void)] = [
        ("Golden Gate", { $0.accent = "#FFC56B"; $0.font = "default"; $0.clockWeight = "ultraLight"; $0.glassTint = 0.25; $0.scrim = 0.45; $0.accentMode = "custom" }),
        ("Midnight", { $0.accent = "#8AB4FF"; $0.font = "default"; $0.clockWeight = "thin"; $0.glassTint = 0.5; $0.scrim = 0.65; $0.accentMode = "custom" }),
        ("Aurora", { $0.accent = "#7EE2A8"; $0.font = "rounded"; $0.clockWeight = "light"; $0.glassTint = 0.3; $0.scrim = 0.5; $0.accentMode = "custom" }),
        ("Sahara", { $0.accent = "#F2A65A"; $0.font = "serif"; $0.clockWeight = "light"; $0.glassTint = 0.2; $0.scrim = 0.4; $0.accentMode = "custom" }),
        ("Wallpaper", { $0.accentMode = "wallpaper"; $0.font = "default"; $0.clockWeight = "ultraLight"; $0.glassTint = 0.15; $0.scrim = 0.35 }),
    ]

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

    func exportTheme() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gateview-theme.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FileManager.default.copyItem(at: Self.url, to: url)
    }

    func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            theme = try Theme.decode(Data(contentsOf: url))
            loadError = nil
        } catch {
            loadError = "Import gagal: \(error.localizedDescription)"
        }
    }

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
