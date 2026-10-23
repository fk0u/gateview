import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var windows: WindowManager
    @ObservedObject var store: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        let theme = store.theme
        let motion = theme.motion && !reduceMotion
        let mood = viewModel.mood
        let moodColor = Color(hex: mood.tint) ?? .black
        let accent = theme.accentMode == "wallpaper" ? viewModel.wallpaperAccent ?? theme.accentColor : theme.accentColor
        return ZStack(alignment: .bottom) {
            // Soft scrim so white text reads on any wallpaper.
            // Mood washes a soft colour into the middle of the scrim.
            LinearGradient(colors: [.clear, moodColor.opacity(mood.tintOpacity), .black.opacity(min(theme.scrim + mood.scrimDelta, 0.95))],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 420 + windows.dockInset + mood.scrimDelta * 400)
                .frame(maxWidth: .infinity)

            HStack(alignment: .bottom, spacing: 40) {
                if theme.panelSide == "left" {
                    panel(theme)
                    Spacer(minLength: 0)
                    leftColumn(theme)
                } else {
                    leftColumn(theme)
                    Spacer(minLength: 0)
                    panel(theme)
                }
            }
            // Entrance: rise + fade once at launch.
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || !motion ? 0 : 24)
            .padding(.horizontal, 72)
            .padding(.bottom, 56 + windows.dockInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .foregroundStyle(.white)
        .tint(accent)
        .environment(\.moodTint, moodColor.opacity(mood.tintOpacity * 0.6))
        .motion(.easeInOut(duration: 3), value: mood, enabled: motion)
        .motion(.easeInOut(duration: 1.2), value: accent, enabled: motion)
        .fontDesign(theme.fontDesign)
        .environment(\.colorScheme, .dark)
        .environment(\.gateMotion, motion)
        .onAppear {
            withAnimation(motion ? .spring(response: 0.9, dampingFraction: 0.85).delay(0.2) : nil) { appeared = true }
        }
        .onPreferenceChange(HitRegionsKey.self) { windows.hitRegions = $0 }
        .task(id: windows.expanded) { await autoCollapse() }
    }

    // MARK: Columns

    private func leftColumn(_ theme: Theme) -> some View {
        VStack(alignment: theme.panelSide == "left" ? .trailing : .leading, spacing: 14) {
            leftDetail(theme)
            card("clock", plate: 12) { _ in
                ClockWidgetView(theme: theme) {
                    if theme.showWeather, let weather = viewModel.weather {
                        card("weather", plate: 8) { _ in WeatherView(weather: weather) }
                    }
                }
            }
            if theme.showStats {
                card("stats", plate: 8) { _ in StatsBarView(monitor: viewModel.stats) }
            }
        }
    }

    /// Details for wallpaper-level widgets open as a glass card above the clock.
    @ViewBuilder private func leftDetail(_ theme: Theme) -> some View {
        Group {
            switch windows.expanded {
            case "clock":
                MonthCalendarView().frame(width: 360).glass(tint: theme.glassTint)
            case "weather":
                if let weather = viewModel.weather {
                    WeatherDetailView(weather: weather, city: theme.city).frame(width: 400).glass(tint: theme.glassTint)
                }
            case "stats":
                StatsDetailView(monitor: viewModel.stats).frame(width: 360).glass(tint: theme.glassTint)
            default:
                EmptyView()
            }
        }
        .contentShape(Rectangle())
        .background(GeometryReader { geo in
            // The open card itself stays interactive (and clicks inside it don't close it).
            Color.clear.preference(key: HitRegionsKey.self,
                                   value: ["clock", "weather", "stats"].contains(windows.expanded ?? "") ? ["detail": geo.frame(in: .global)] : [:])
        })
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
    }

    private func panel(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            let visible = theme.widgetOrder.filter { key in
                switch key {
                case "agenda": return theme.showAgenda
                case "nowPlaying": return theme.showNowPlaying
                default: return true
                }
            }
            ForEach(Array(visible.enumerated()), id: \.element) { index, key in
                panelWidget(key, theme: theme, divider: index > 0)
            }
        }
        .frame(width: 380)
        .glass(tint: theme.glassTint)
    }

    @ViewBuilder private func panelWidget(_ key: String, theme: Theme, divider: Bool) -> some View {
        switch key {
        case "prayer":
            if divider { Divider().overlay(.white.opacity(0.15)) }
            card("prayer") { expanded in
                if expanded {
                    PrayerDetailView(prayers: viewModel.prayers, timings: viewModel.todayTimings, week: viewModel.week, store: store)
                        .task { await viewModel.loadWeek() }
                } else {
                    PrayerWidgetView(prayers: viewModel.prayers, error: viewModel.prayerError, city: theme.city)
                }
            }
        case "agenda":
            if divider { Divider().overlay(.white.opacity(0.15)) }
            card("agenda") { expanded in
                if expanded {
                    AgendaDetailView(events: viewModel.detailEvents())
                } else {
                    CalendarWidgetView(events: viewModel.events, authorized: viewModel.calendarAuthorized)
                }
            }
        case "nowPlaying":
            NowPlayingSlot(service: viewModel.nowPlaying, windows: windows, divider: divider, motion: theme.motion)
        default:
            EmptyView()
        }
    }

    private func card<Content: View>(_ id: String, plate: CGFloat = 0, @ViewBuilder _ content: @escaping (Bool) -> Content) -> some View {
        InteractiveCard(id: id, windows: windows, plate: plate, motion: store.theme.motion, content: content)
    }

    /// Close an open detail after 20 s without the cursor on it.
    private func autoCollapse() async {
        guard let id = windows.expanded else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, windows.expanded == id else { return }
            if windows.hovered == nil {
                withAnimation(.easeOut(duration: 0.3)) { windows.expanded = nil }
                return
            }
        }
    }
}

/// Observes the service directly (nested ObservableObjects don't propagate).
private struct NowPlayingSlot: View {
    @ObservedObject var service: NowPlayingService
    @ObservedObject var windows: WindowManager
    let divider: Bool
    let motion: Bool

    var body: some View {
        // Shown while playing, or while its detail is open (so pausing there doesn't make it vanish).
        if let track = service.track, track.isPlaying || windows.expanded == "nowPlaying" {
            if divider { Divider().overlay(.white.opacity(0.15)) }
            InteractiveCard(id: "nowPlaying", windows: windows, motion: motion) { expanded in
                if expanded {
                    NowPlayingDetailView(track: track, service: service)
                } else {
                    NowPlayingView(track: track)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

extension View {
    /// Real behind-window blur of the wallpaper (SwiftUI Material only blurs within the window).
    func glass(tint: Double) -> some View {
        modifier(Glass(tint: tint))
    }
}

private struct MoodTintKey: EnvironmentKey { static let defaultValue = Color.clear }

extension EnvironmentValues {
    var moodTint: Color {
        get { self[MoodTintKey.self] }
        set { self[MoodTintKey.self] = newValue }
    }
}

private struct Glass: ViewModifier {
    let tint: Double
    @Environment(\.moodTint) private var moodTint

    func body(content: Content) -> some View {
        content
            .padding(24)
            .background(moodTint.background(Color.black.opacity(tint)).background(VisualEffectBlur()))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua) // dark glass keeps white text legible
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
