import Combine
import EventKit
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var prayers: [Prayer] = []
    @Published private(set) var prayerError: String?
    @Published private(set) var events: [Agenda] = []
    @Published private(set) var calendarAuthorized = false
    @Published private(set) var weather: Weather?

    let nowPlaying = NowPlayingService()
    let reminders = ReminderService()
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
        ]
        Task { await refresh() }

        // Location / iqamah edits (Settings or theme.json) → refetch. dropFirst: init already loads.
        store.$theme.map(\.locationKey).removeDuplicates().dropFirst()
            .sink { [weak self] _ in Task { await self?.refresh(force: true) } }
            .store(in: &subscriptions)
        store.$theme.map(\.showNowPlaying).removeDuplicates()
            .sink { [weak self] on in on ? self?.nowPlaying.start() : self?.nowPlaying.stop() }
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
        if force { await loadWeather() }
    }

    func rescheduleReminders() async {
        await reminders.schedule(prayers)
    }

    private func loadPrayers(force: Bool) async {
        do {
            let t = store.theme
            let day = try await prayerService.todayTimings(city: t.city, country: t.country, method: t.prayerMethod, force: force)
            prayers = PrayerTimeService.prayers(from: day, iqamah: t.iqamah)
            prayerError = nil
            await rescheduleReminders()
        } catch {
            if prayers.isEmpty { prayerError = "Prayer times unavailable" }
        }
    }

    private func loadWeather() async {
        if let fresh = try? await weatherService.current(latitude: store.theme.latitude, longitude: store.theme.longitude) { weather = fresh } // keep last value on failure
    }

    private func loadEvents() {
        events = calendarAuthorized ? calendarService.upcomingEvents() : []
    }
}
