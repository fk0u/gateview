import Combine
import SwiftUI
import EventKit
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var prayers: [Prayer] = []
    @Published private(set) var prayerError: String?
    @Published private(set) var events: [Agenda] = []
    @Published private(set) var calendarAuthorized = false
    @Published private(set) var weather: Weather?
    @Published private(set) var todayTimings: [String: String] = [:] // incl. Imsak, Sunrise for the detail card
    @Published private(set) var week: [PrayerDay] = []
    @Published private(set) var mood = Mood()
    @Published private(set) var wallpaperAccent: Color?
    /// Settings → "Preview" shows an effect for 15 s regardless of the real weather.
    @Published private(set) var effectPreview: Int?

    let nowPlaying = NowPlayingService()
    let reminders = ReminderService()
    let remindersService = RemindersService()
    let stats = SystemStatsMonitor()
    let gallery = GalleryService()
    private lazy var wallpaper = WallpaperColorService { [weak self] color in
        self?.wallpaperAccent = color.map(Color.init(nsColor:))
    }
    private let prayerService = PrayerTimeService()
    private let calendarService = CalendarService()
    private let weatherService = WeatherService()
    private let store = ThemeStore.shared
    private var observers: [NSObjectProtocol] = []
    private var subscriptions: Set<AnyCancellable> = []

    init() {
        let center = NotificationCenter.default
        observers = [
            // Midnight rollover → fetch new day's schedule & agenda.
            center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in await self.refresh() }
            },
            center.addObserver(forName: .EKEventStoreChanged, object: calendarService.store, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.loadEvents() }
            },
            center.addObserver(forName: .EKEventStoreChanged, object: remindersService.store, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.remindersService.load() }
            },
        ]
        Task { await refresh() }
        // Debug: `GateView -GateViewPreviewEffect 63` forces a weather effect (used to measure CPU).
        let code = UserDefaults.standard.integer(forKey: "GateViewPreviewEffect"); if code > 0 { effectPreview = code }

        // Location / iqamah edits (Settings or theme.json) → refetch. dropFirst: init already loads.
        store.$theme.map(\.locationKey).removeDuplicates().dropFirst()
            .sink { [weak self] _ in Task { await self?.refresh(force: true) } }
            .store(in: &subscriptions)
        store.$theme.map { "\($0.reminderMode)|\($0.reminderSound)|\($0.adhanPath)|\($0.adhanPaths.sorted { $0.key < $1.key })|\($0.adhanVolume)|\($0.reminders.sorted { $0.key < $1.key })" }
            .removeDuplicates().dropFirst()
            .sink { [weak self] _ in Task { await self?.rescheduleReminders() } }
            .store(in: &subscriptions)
        store.$theme.map(\.temperatureUnit).removeDuplicates().dropFirst()
            .sink { [weak self] _ in Task { await self?.loadWeather() } }
            .store(in: &subscriptions)
        store.$theme.map(\.mood).removeDuplicates().dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.updateMood() } }
            .store(in: &subscriptions)
        store.$theme.map { "\($0.panelWidgets.contains("gallery"))|\($0.galleryFolder)|\($0.galleryInterval)" }.removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let t = self.store.theme
                    t.panelWidgets.contains("gallery") ? self.gallery.start(folder: t.galleryFolder, interval: t.galleryInterval) : self.gallery.stop()
                }
            }
            .store(in: &subscriptions)
        store.$theme.map(\.accentMode).removeDuplicates()
            .sink { [weak self] mode in mode == "wallpaper" ? self?.wallpaper.start() : self?.wallpaper.stop() }
            .store(in: &subscriptions)
        // Mood: recomputed at each minute boundary (and when the schedule loads).
        Task { [weak self] in
            while !Task.isCancelled {
                self?.updateMood()
                let wait = 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        store.$theme.map(\.showStats).removeDuplicates()
            .sink { [weak self] on in on ? self?.stats.start() : self?.stats.stop() }
            .store(in: &subscriptions)
        store.$theme.map { $0.panelWidgets.contains("nowPlaying") }.removeDuplicates()
            .sink { [weak self] on in on ? self?.nowPlaying.start() : self?.nowPlaying.stop() }
            .store(in: &subscriptions)
        store.$theme.map { $0.panelWidgets.contains("reminders") }.removeDuplicates()
            .sink { [weak self] on in Task { @MainActor in
                guard let self else { return }
                if on {
                    if !self.remindersService.authorized { _ = await self.remindersService.requestAccess() }
                    self.remindersService.load()
                }
            } }
            .store(in: &subscriptions)
        Task { [weak self] in
            while !Task.isCancelled {
                await self?.loadWeather()
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
            }
        }
    }

    func refresh(force: Bool = false) async {
        await loadPrayers(force: force)
        if !calendarAuthorized {
            calendarAuthorized = await calendarService.requestAccess()
        }
        loadEvents()
        // Only ask for Reminders access when the widget is actually in the panel.
        if store.theme.panelWidgets.contains("reminders") {
            if !remindersService.authorized { _ = await remindersService.requestAccess() }
            remindersService.load()
        }
        if force { await loadWeather() }
    }

    func previewEffect(_ code: Int) {
        effectPreview = code
        Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if effectPreview == code { effectPreview = nil }
        }
    }

    private func updateMood() {
        let next = store.theme.mood ? MoodEngine.mood(at: .now, prayers: prayers) : Mood()
        if next != mood { mood = next }
    }

    func loadWeek() async {
        guard week.isEmpty else { return }
        let t = store.theme
        week = await prayerService.week(city: t.city, country: t.country, method: t.prayerMethod)
    }

    func events(on day: Date) -> [Agenda] {
        calendarAuthorized ? calendarService.events(on: day) : []
    }

    func detailEvents() -> [Agenda] {
        calendarAuthorized ? calendarService.upcomingEvents(limit: 8, extraDays: 1) : []
    }

    func rescheduleReminders() async {
        await reminders.schedule(prayers, theme: store.theme)
    }

    private func loadPrayers(force: Bool) async {
        do {
            let t = store.theme
            let day = try await prayerService.todayTimings(city: t.city, country: t.country, method: t.prayerMethod, force: force)
            prayers = PrayerTimeService.prayers(from: day, iqamah: t.iqamah)
            todayTimings = day.timings
            updateMood()
            week = []
            prayerError = nil
            await rescheduleReminders()
        } catch {
            if prayers.isEmpty { prayerError = "Prayer times unavailable" }
        }
    }

    private func loadWeather() async {
        if let fresh = try? await weatherService.fetch(latitude: store.theme.latitude, longitude: store.theme.longitude, unit: store.theme.temperatureUnit) { weather = fresh } // keep last value on failure
    }

    private func loadEvents() {
        events = calendarAuthorized ? calendarService.upcomingEvents() : []
    }
}
