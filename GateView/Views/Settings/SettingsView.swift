import ServiceManagement
import SwiftUI

/// Full settings app: sidebar + sections, all bound to the live theme (changes apply instantly).
struct SettingsView: View {
    @ObservedObject var store: ThemeStore
    @ObservedObject var windows: WindowManager
    let testReminder: () -> Void
    let previewWeather: (Int) -> Void
    @State private var section: Section? = .appearance

    enum Section: String, CaseIterable, Identifiable {
        case general = "General", appearance = "Appearance", motion = "Motion & Mood", widgets = "Widgets"
        case prayer = "Prayer", weather = "Weather", file = "Theme File", about = "About"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintpalette"
            case .motion: return "sparkles"
            case .widgets: return "square.grid.2x2"
            case .prayer: return "moon.stars"
            case .weather: return "cloud.sun"
            case .file: return "doc.text"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Form { content }
                .formStyle(.grouped)
                .navigationTitle(section?.rawValue ?? "")
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    @ViewBuilder private var content: some View {
        switch section ?? .appearance {
        case .general: GeneralSection(store: store, windows: windows)
        case .appearance: AppearanceSection(store: store)
        case .motion: MotionSection(store: store, preview: previewWeather)
        case .widgets: WidgetsSection(store: store)
        case .prayer: PrayerSection(store: store, testReminder: testReminder)
        case .weather: WeatherSection(store: store)
        case .file: FileSection(store: store)
        case .about: AboutSection()
        }
    }
}

// MARK: - Sections

private struct GeneralSection: View {
    @ObservedObject var store: ThemeStore
    @ObservedObject var windows: WindowManager

    var body: some View {
        SwiftUI.Section {
            Toggle("Launch at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { on in
                try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }))
            Toggle("Interactive widgets", isOn: $store.theme.interactive)
            Text("Hover a widget to highlight it, click to open details. Everything else stays click-through.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Click-through everywhere", isOn: $windows.clickThrough)
        }
        SwiftUI.Section("Display") {
            Picker("Show on", selection: $store.theme.displayIndex) {
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { i, screen in
                    Text(i == 0 ? "\(screen.localizedName) (main)" : screen.localizedName).tag(i)
                }
            }
        }
    }
}

private struct AppearanceSection: View {
    @ObservedObject var store: ThemeStore

    var body: some View {
        SwiftUI.Section { ThemePreview(theme: store.theme) }
        SwiftUI.Section("Presets") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                ForEach(Theme.presets, id: \.name) { preset in
                    Button {
                        withAnimation { preset.apply(&store.theme) }
                    } label: {
                        PresetSwatch(name: preset.name, theme: { var t = store.theme; preset.apply(&t); return t }())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        SwiftUI.Section("Accent") {
            Picker("Accent colour", selection: $store.theme.accentMode) {
                Text("Custom").tag("custom")
                Text("Follow wallpaper").tag("wallpaper")
            }
            .pickerStyle(.segmented)
            if store.theme.accentMode == "custom" {
                ColorPicker("Colour", selection: Binding(
                    get: { store.theme.accentColor },
                    set: { store.theme.accent = $0.hex }
                ), supportsOpacity: false)
            }
        }
        SwiftUI.Section("Clock") {
            Picker("Font", selection: $store.theme.font) {
                Text("San Francisco").tag("default")
                Text("Rounded").tag("rounded")
                Text("New York (serif)").tag("serif")
                Text("Monospaced").tag("monospaced")
            }
            Picker("Weight", selection: $store.theme.clockWeight) {
                ForEach(["ultraLight", "thin", "light", "regular", "medium", "bold"], id: \.self) { Text($0).tag($0) }
            }
            LabeledContent("Size") {
                Slider(value: $store.theme.clockSize, in: 80...240, step: 4)
                Text("\(Int(store.theme.clockSize))").monospacedDigit().frame(width: 32)
            }
            Toggle("Show seconds", isOn: $store.theme.showSeconds)
            TextField("Greeting name", text: $store.theme.greetingName, prompt: Text("e.g. Ghani"))
        }
        SwiftUI.Section("Layout & glass") {
            Picker("Panel side", selection: $store.theme.panelSide) {
                Text("Left").tag("left")
                Text("Right").tag("right")
            }
            .pickerStyle(.segmented)
            LabeledContent("Glass darkness") { Slider(value: $store.theme.glassTint, in: 0...0.8) }
            LabeledContent("Bottom gradient") { Slider(value: $store.theme.scrim, in: 0...0.9) }
        }
    }
}

private struct MotionSection: View {
    @ObservedObject var store: ThemeStore
    let preview: (Int) -> Void

    var body: some View {
        SwiftUI.Section {
            Toggle("Animations", isOn: $store.theme.motion)
            Text("Digit rolls, panel transitions and detail cards. Follows Reduce Motion in Accessibility.")
                .font(.caption).foregroundStyle(.secondary)
        }
        SwiftUI.Section {
            Toggle("Mood by time & prayer", isOn: $store.theme.mood)
            Text("Cool dawn at Subuh, golden before Maghrib, calm and dim after Isya.")
                .font(.caption).foregroundStyle(.secondary)
        }
        SwiftUI.Section("Live weather") {
            Picker("Weather effects", selection: $store.theme.weatherEffects) {
                Text("Off").tag("off")
                Text("Subtle").tag("subtle")
                Text("Full").tag("full")
            }
            .pickerStyle(.segmented)
            Text("Rain, drizzle, storm and fog behind the widgets. Paused when the desktop is covered or in Low Power Mode.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Preview 15 s").foregroundStyle(.secondary)
                ForEach([("Gerimis", 53), ("Hujan", 63), ("Badai", 95), ("Kabut", 45)], id: \.1) { name, code in
                    Button(name) { preview(code) }
                }
            }
            .disabled(store.theme.weatherEffects == "off")
        }
    }
}

private struct WidgetsSection: View {
    @ObservedObject var store: ThemeStore
    private static let names = ["prayer": ("Prayer times", "moon.stars.fill"), "agenda": ("Agenda", "calendar"),
                                "nowPlaying": ("Now Playing", "music.note")]

    var body: some View {
        SwiftUI.Section("Left side") {
            Toggle("Weather", isOn: $store.theme.showWeather)
            Toggle("System stats", isOn: $store.theme.showStats)
        }
        SwiftUI.Section {
            List {
                ForEach(store.theme.widgetOrder, id: \.self) { key in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Label(Self.names[key]?.0 ?? key, systemImage: Self.names[key]?.1 ?? "square")
                        Spacer()
                        Toggle("", isOn: binding(for: key)).labelsHidden()
                    }
                }
                .onMove { store.theme.widgetOrder.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 120)
        } header: {
            Text("Glass panel — drag to reorder")
        }
    }

    private func binding(for key: String) -> Binding<Bool> {
        switch key {
        case "agenda": return $store.theme.showAgenda
        case "nowPlaying": return $store.theme.showNowPlaying
        default: return .constant(true) // prayer is the panel's anchor
        }
    }
}

private struct PrayerSection: View {
    @ObservedObject var store: ThemeStore
    let testReminder: () -> Void
    @State private var query = ""
    @State private var results: [WeatherService.Place] = []
    @State private var searching = false

    private static let keys = [("Fajr", "Subuh"), ("Dhuhr", "Dzuhur / Jumat"), ("Asr", "Ashar"), ("Maghrib", "Maghrib"), ("Isha", "Isya")]

    var body: some View {
        SwiftUI.Section("Location") {
            LabeledContent("Current", value: "\(store.theme.city), \(store.theme.country)")
            HStack {
                TextField("Search city", text: $query, prompt: Text("e.g. Balikpapan"))
                    .onSubmit(search)
                Button("Search", action: search).disabled(query.count < 2)
                if searching { ProgressView().controlSize(.small) }
            }
            ForEach(results) { place in
                Button {
                    store.theme.city = place.name
                    store.theme.country = place.country ?? store.theme.country
                    store.theme.latitude = place.latitude
                    store.theme.longitude = place.longitude
                    results = []
                    query = ""
                } label: {
                    Label([place.name, place.admin1, place.country].compactMap { $0 }.joined(separator: ", "), systemImage: "mappin.circle")
                }
                .buttonStyle(.link)
            }
            Picker("Calculation method", selection: $store.theme.prayerMethod) {
                Text("Kemenag RI").tag(20)
                Text("JAKIM Malaysia").tag(17)
                Text("MUIS Singapore").tag(11)
                Text("Muslim World League").tag(3)
                Text("Umm al-Qura").tag(4)
                Text("Egyptian").tag(5)
                Text("ISNA").tag(2)
            }
        }
        SwiftUI.Section("Iqomah & reminder per prayer") {
            ForEach(Self.keys, id: \.0) { key, label in
                HStack {
                    Toggle(label, isOn: Binding(
                        get: { store.theme.reminders[key] ?? true },
                        set: { store.theme.reminders[key] = $0 }
                    ))
                    Spacer()
                    Stepper(value: Binding(
                        get: { store.theme.iqamah[key] ?? 10 },
                        set: { store.theme.iqamah[key] = $0 }
                    ), in: 0...45) {
                        Text("iqomah \(store.theme.iqamah[key] ?? 10) min").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
        SwiftUI.Section("Reminder") {
            Picker("Mode", selection: $store.theme.reminderMode) {
                ForEach(ReminderService.modes, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Picker("Chime sound", selection: $store.theme.reminderSound) {
                    ForEach(ReminderService.sounds, id: \.self) { Text($0).tag($0) }
                }
                Button { ReminderService.play(store.theme.reminderSound) } label: { Image(systemName: "speaker.wave.2.fill") }
            }
            Button("Send test reminder", action: testReminder)
        }
    }

    private func search() {
        guard query.count >= 2 else { return }
        searching = true
        Task {
            results = (try? await WeatherService.search(query)) ?? []
            searching = false
        }
    }
}

private struct WeatherSection: View {
    @ObservedObject var store: ThemeStore

    var body: some View {
        SwiftUI.Section {
            Picker("Temperature", selection: $store.theme.temperatureUnit) {
                Text("°C").tag("celsius")
                Text("°F").tag("fahrenheit")
            }
            .pickerStyle(.segmented)
            LabeledContent("Coordinates", value: String(format: "%.4f, %.4f", store.theme.latitude, store.theme.longitude))
            Text("Weather uses the location chosen in Prayer. Data: Open-Meteo, refreshed every 30 minutes.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct FileSection: View {
    @ObservedObject var store: ThemeStore

    var body: some View {
        SwiftUI.Section {
            LabeledContent("Location", value: "~/.config/gateview/theme.json")
            if let error = store.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            HStack {
                Button("Open in Editor") { store.openInEditor() }
                Button("Show in Finder") { store.reveal() }
            }
            HStack {
                Button("Import…") { store.importTheme() }
                Button("Export…") { store.exportTheme() }
                Spacer()
                Button("Reset to Default", role: .destructive) { store.reset() }
            }
        } footer: {
            Text("Edit theme.json in any editor; GateView reloads it the moment you save. Missing keys keep their defaults.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct AboutSection: View {
    @State private var update: String?
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    var body: some View {
        SwiftUI.Section {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading) {
                    Text("GateView").font(.title2.weight(.semibold))
                    Text("Version \(version)").foregroundStyle(.secondary)
                }
            }
            Link("github.com/fk0u/gateview", destination: URL(string: "https://github.com/fk0u/gateview")!)
            HStack {
                Button("Check for Updates", action: check)
                if let update { Text(update).foregroundStyle(.secondary) }
            }
        }
    }

    private func check() {
        update = "Checking…"
        Task {
            struct Release: Decodable { let tag_name: String }
            let url = URL(string: "https://api.github.com/repos/fk0u/gateview/releases/latest")!
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let latest = try? JSONDecoder().decode(Release.self, from: data).tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            else { update = "No releases found"; return }
            update = latest.compare(version, options: .numeric) == .orderedDescending
                ? "Version \(latest) is available on GitHub" : "You're up to date"
        }
    }
}

// MARK: - Preview pieces

private struct ThemePreview: View {
    let theme: Theme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hex: "#3A4A6B")!, Color(hex: "#1A2033")!], startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.clear, .black.opacity(theme.scrim)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(theme.greetingName.isEmpty ? "Good Evening" : "Good Evening, \(theme.greetingName)").font(.system(size: 11)).opacity(0.85)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("19:10").font(.system(size: theme.clockSize * 0.3, weight: theme.clockFontWeight))
                        if theme.showSeconds { Text("42").font(.system(size: theme.clockSize * 0.06)).foregroundStyle(.tint) }
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Isya").font(.system(size: 13, weight: .semibold))
                    Text("07:18").font(.system(size: 16, weight: .light).monospacedDigit()).foregroundStyle(.tint)
                }
                .padding(10)
                .frame(width: 110, alignment: .leading)
                .background(.black.opacity(0.2 + theme.glassTint * 0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.18)))
            }
            .environment(\.layoutDirection, theme.panelSide == "left" ? .rightToLeft : .leftToRight)
            .padding(16)
        }
        .foregroundStyle(.white)
        .tint(theme.accentColor)
        .fontDesign(theme.fontDesign)
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PresetSwatch: View {
    let name: String
    let theme: Theme

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#2B3550")!, .black.opacity(0.6 + theme.scrim * 0.4)], startPoint: .top, endPoint: .bottom))
                .overlay(Text("12:30").font(.system(size: 18, weight: theme.clockFontWeight)).fontDesign(theme.fontDesign).foregroundStyle(.white))
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(theme.accentMode == "wallpaper"
                                  ? AnyShapeStyle(AngularGradient(colors: [.orange, .pink, .blue, .green, .orange], center: .center))
                                  : AnyShapeStyle(theme.accentColor))
                        .frame(width: 12, height: 12).padding(6)
                }
                .frame(height: 56)
            Text(name).font(.caption)
        }
    }
}
