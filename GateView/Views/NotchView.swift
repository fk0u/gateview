import SwiftUI

/// Top-edge hardware-style Notch (sticky in front of all windows, flush with y = 0 — NOT a floating Dynamic Island).
struct NotchView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var stats: SystemStatsMonitor
    @ObservedObject var windows: WindowManager
    @ObservedObject var store: ThemeStore

    private var expanded: Bool { windows.expanded == "notch" }
    private var theme: Theme { store.theme }

    var body: some View {
        let lang = theme.displayLanguage
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let phase = PrayerTimeService.phase(at: ctx.date, in: viewModel.prayers)
                if expanded {
                    expandedBody(now: ctx.date, phase: phase, lang: lang)
                } else {
                    compactBody(now: ctx.date, phase: phase, lang: lang)
                }
            }
        }
        .frame(width: expanded ? 440 : 280)
        .background(Color(red: 0.024, green: 0.031, blue: 0.051))
        .clipShape(NotchShape(bottomRadius: expanded ? 24 : 18))
        .overlay(
            NotchShape(bottomRadius: expanded ? 24 : 18)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 14, y: 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                windows.expanded = expanded ? nil : "notch"
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .tint(theme.accentColor)
        .fontDesign(theme.fontDesign)
        .environment(\.colorScheme, .dark)
    }

    private func compactBody(now: Date, phase: PrayerPhase?, lang: String) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                if let phase {
                    Text(phasePrayer(phase).name)
                        .lineLimit(1)
                        .opacity(0.88)
                    Text(phaseSubtitle(phase, now: now, compact: true, lang: lang))
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .lineLimit(1)
                } else {
                    Text(theme.city)
                        .lineLimit(1)
                        .opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            cameraDot

            HStack(spacing: 5) {
                if let track = nowPlaying.track, track.isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text(track.title)
                        .lineLimit(1)
                        .opacity(0.88)
                } else if let w = viewModel.weather {
                    Text("\(w.temperature)°")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text(w.label)
                        .lineLimit(1)
                        .opacity(0.8)
                } else {
                    Text("CPU \(stats.stats.cpu)%")
                        .monospacedDigit()
                        .opacity(0.75)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 16)
        .frame(height: 32)
    }

    private func expandedBody(now: Date, phase: PrayerPhase?, lang: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(theme.city)
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.85)
                Spacer()
                cameraDot
                Spacer()
                HStack(spacing: 8) {
                    if let w = viewModel.weather {
                        Text("\(w.temperature)° \(w.label)")
                    }
                    Text("CPU \(stats.stats.cpu)% · RAM \(stats.stats.ram)%")
                        .monospacedDigit()
                }
                .font(.system(size: 11))
                .opacity(0.72)
            }

            if let track = nowPlaying.track {
                HStack(spacing: 12) {
                    if let art = track.artwork {
                        Image(nsImage: art)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.08))
                            .frame(width: 40, height: 40)
                            .overlay(Image(systemName: "music.note").opacity(0.6))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(track.artist).font(.system(size: 11)).opacity(0.7).lineLimit(1)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Button { nowPlaying.perform(.previous) } label: { Image(systemName: "backward.fill") }
                        Button { nowPlaying.perform(.toggle) } label: {
                            Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                                .foregroundStyle(.tint)
                        }
                        Button { nowPlaying.perform(.next) } label: { Image(systemName: "forward.fill") }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                }
                .padding(10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !viewModel.prayers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(phase.map { phasePrayer($0).name } ?? L10n.tr(lang, "Jadwal Sholat", "Prayer times"))
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        if let phase {
                            Text(phaseSubtitle(phase, now: now, compact: false, lang: lang))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.tint)
                                .monospacedDigit()
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(viewModel.prayers) { p in
                            let isNext = phase.map { phasePrayer($0).key == p.key } ?? false
                            VStack(spacing: 2) {
                                Text(p.name).font(.system(size: 10)).opacity(0.75)
                                Text(p.time.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.tint)
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(.white.opacity(isNext ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                }
                .padding(10)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    private var cameraDot: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(red: 0.14, green: 0.19, blue: 0.28), Color(red: 0.04, green: 0.06, blue: 0.09)],
                                 center: .topLeading, startRadius: 0, endRadius: 6))
            .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
            .frame(width: 8, height: 8)
    }

    private func phasePrayer(_ phase: PrayerPhase) -> Prayer {
        switch phase {
        case .upcoming(let p), .iqamah(let p), .ongoing(let p): return p
        }
    }

    private func phaseSubtitle(_ phase: PrayerPhase, now: Date, compact: Bool, lang: String) -> String {
        switch phase {
        case .upcoming(let p):
            let cd = PrayerTimeService.countdown(to: p.time, from: now)
            return compact ? cd : "\(L10n.tr(lang, "adzan dalam", "adzan in")) \(cd)"
        case .iqamah(let p):
            let cd = PrayerTimeService.countdown(to: p.iqamah ?? p.time, from: now)
            return compact ? cd : "\(L10n.tr(lang, "Iqomah dalam", "Iqomah in")) \(cd)"
        case .ongoing:
            return L10n.tr(lang, "berjamaah", "ongoing")
        }
    }
}

/// Flat top edge flush with the screen bezel, smoothly rounded bottom corners.
private struct NotchShape: InsettableShape {
    var bottomRadius: CGFloat
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> NotchShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let rad = min(bottomRadius, min(r.width / 2, r.height))
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addArc(center: CGPoint(x: r.maxX - rad, y: r.maxY - rad), radius: rad, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + rad, y: r.maxY - rad), radius: rad, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}
