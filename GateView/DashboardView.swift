import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var windows: WindowManager
    @ObservedObject var store: ThemeStore

    var body: some View {
        let theme = store.theme
        return ZStack(alignment: .bottom) {
            // Soft scrim so white text reads on any wallpaper.
            LinearGradient(colors: [.clear, .black.opacity(theme.scrim)], startPoint: .top, endPoint: .bottom)
                .frame(height: 420 + windows.dockInset)
                .frame(maxWidth: .infinity)

            HStack(alignment: .bottom, spacing: 40) {
                if theme.panelSide == "left" {
                    panel(theme)
                    Spacer(minLength: 0)
                    clock(theme)
                } else {
                    clock(theme)
                    Spacer(minLength: 0)
                    panel(theme)
                }
            }
            .padding(.horizontal, 72)
            .padding(.bottom, 56 + windows.dockInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .foregroundStyle(.white)
        .tint(theme.accentColor)
        .fontDesign(theme.fontDesign)
        .environment(\.colorScheme, .dark)
    }

    private func clock(_ theme: Theme) -> some View {
        VStack(alignment: theme.panelSide == "left" ? .trailing : .leading, spacing: 14) {
            ClockWidgetView(theme: theme, weather: theme.showWeather ? viewModel.weather : nil)
            if theme.showStats { StatsBarView() }
        }
    }

    private func panel(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            PrayerWidgetView(prayers: viewModel.prayers, error: viewModel.prayerError, city: theme.city)
            if theme.showAgenda {
                Divider().overlay(.white.opacity(0.15))
                CalendarWidgetView(events: viewModel.events, authorized: viewModel.calendarAuthorized)
            }
            if theme.showNowPlaying { NowPlayingSlot(service: viewModel.nowPlaying) }
        }
        .frame(width: 380)
        .glass(tint: theme.glassTint)
    }
}

/// Observes the service directly (nested ObservableObjects don't propagate).
private struct NowPlayingSlot: View {
    @ObservedObject var service: NowPlayingService

    var body: some View {
        Group {
            if let track = service.track {
                Divider().overlay(.white.opacity(0.15))
                NowPlayingView(track: track)
            }
        }
    }
}

extension View {
    /// Real behind-window blur of the wallpaper (SwiftUI Material only blurs within the window).
    func glass(tint: Double) -> some View {
        padding(24)
            .background(Color.black.opacity(tint).background(VisualEffectBlur()))
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
