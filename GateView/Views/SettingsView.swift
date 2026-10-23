import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ThemeStore

    private static let prayerKeys = [("Fajr", "Subuh"), ("Dhuhr", "Dzuhur / Jumat"), ("Asr", "Ashar"), ("Maghrib", "Maghrib"), ("Isha", "Isya")]

    var body: some View {
        Form {
            Section("Tampilan") {
                ColorPicker("Warna aksen", selection: Binding(
                    get: { store.theme.accentColor },
                    set: { store.theme.accent = $0.hex }
                ), supportsOpacity: false)
                Picker("Font", selection: $store.theme.font) {
                    Text("San Francisco").tag("default")
                    Text("Rounded").tag("rounded")
                    Text("Serif (New York)").tag("serif")
                    Text("Monospaced").tag("monospaced")
                }
                Picker("Ketebalan jam", selection: $store.theme.clockWeight) {
                    ForEach(["ultraLight", "thin", "light", "regular", "medium", "bold"], id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Ukuran jam") {
                    Slider(value: $store.theme.clockSize, in: 80...240, step: 4)
                    Text("\(Int(store.theme.clockSize))").monospacedDigit().frame(width: 32)
                }
                Toggle("Tampilkan detik", isOn: $store.theme.showSeconds)
                Picker("Posisi panel", selection: $store.theme.panelSide) {
                    Text("Kanan").tag("right")
                    Text("Kiri").tag("left")
                }
                .pickerStyle(.segmented)
                LabeledContent("Gelap kaca") { Slider(value: $store.theme.glassTint, in: 0...0.8) }
                LabeledContent("Gradasi bawah") { Slider(value: $store.theme.scrim, in: 0...0.9) }
                TextField("Nama sapaan", text: $store.theme.greetingName)
            }

            Section("Widget") {
                Toggle("Cuaca", isOn: $store.theme.showWeather)
                Toggle("Agenda", isOn: $store.theme.showAgenda)
                Toggle("Now Playing", isOn: $store.theme.showNowPlaying)
                Toggle("System Stats", isOn: $store.theme.showStats)
            }

            Section("Lokasi") {
                TextField("Kota", text: $store.theme.city)
                TextField("Negara", text: $store.theme.country)
                TextField("Latitude (cuaca)", value: $store.theme.latitude, format: .number)
                TextField("Longitude (cuaca)", value: $store.theme.longitude, format: .number)
                Picker("Metode hisab", selection: $store.theme.prayerMethod) {
                    Text("Kemenag RI").tag(20)
                    Text("JAKIM Malaysia").tag(17)
                    Text("MUIS Singapura").tag(11)
                    Text("Muslim World League").tag(3)
                    Text("Umm al-Qura").tag(4)
                }
            }

            Section("Iqomah (menit setelah adzan)") {
                ForEach(Self.prayerKeys, id: \.0) { key, label in
                    Stepper(value: Binding(
                        get: { store.theme.iqamah[key] ?? 10 },
                        set: { store.theme.iqamah[key] = $0 }
                    ), in: 0...45) {
                        LabeledContent(label, value: "\(store.theme.iqamah[key] ?? 10) menit")
                    }
                }
            }

            Section {
                if let error = store.loadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                HStack {
                    Button("Edit theme.json…") { store.openInEditor() }
                    Button("Show in Finder") { store.reveal() }
                    Spacer()
                    Button("Reset ke Default", role: .destructive) { store.reset() }
                }
            } footer: {
                Text("Semua pengaturan tersimpan di ~/.config/gateview/theme.json. Edit file itu langsung dan GateView akan memuat ulang otomatis.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
    }
}
