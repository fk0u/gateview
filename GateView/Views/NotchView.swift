import SwiftUI
import UniformTypeIdentifiers

/// Multi-section sticky Top-Edge Notch Command Center (flush with y = 0, above all windows).
/// Sections: Hub · Focus (Pomodoro) · Shelf (File Tray + AirDrop) · Clip (Clipboard History) · Notes & Reminders · Tools.
struct NotchView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case hub = "Hub"
        case focus = "Focus"
        case shelf = "Shelf"
        case clip = "Clip"
        case notes = "Notes"
        case tools = "Tools"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .hub: return "square.grid.2x2.fill"
            case .focus: return "timer"
            case .shelf: return "tray.and.arrow.down.fill"
            case .clip: return "doc.on.clipboard.fill"
            case .notes: return "note.text"
            case .tools: return "bolt.fill"
            }
        }
    }

    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var stats: SystemStatsMonitor
    @ObservedObject var productivity: NotchProductivityService
    @ObservedObject var notesStore: NotesStore
    @ObservedObject var reminders: RemindersService
    @ObservedObject var windows: WindowManager
    @ObservedObject var store: ThemeStore

    @State private var tab: Tab = .hub
    @State private var isDropTargeted = false
    @State private var clipQuery = ""
    @State private var newReminderTitle = ""
    @State private var newBookmarkTitle = ""
    @State private var newBookmarkURL = ""

    private var expanded: Bool { windows.expanded == "notch" }
    private var theme: Theme { store.theme }

    var body: some View {
        let lang = theme.displayLanguage
        VStack(spacing: 0) {
            if expanded {
                expandedBody(lang: lang)
            } else {
                compactBody(lang: lang)
            }
        }
        .frame(width: expanded ? 548 : 312)
        .background(Color(red: 0.024, green: 0.031, blue: 0.051))
        .clipShape(NotchShape(bottomRadius: expanded ? 24 : 18))
        .overlay(
            NotchShape(bottomRadius: expanded ? 24 : 18)
                .strokeBorder(isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.14)), lineWidth: isDropTargeted ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.58), radius: 16, y: 8)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .tint(theme.accentColor)
        .fontDesign(theme.fontDesign)
        .environment(\.colorScheme, .dark)
        .onChange(of: tab) { next in
            if expanded && (next == .notes || next == .clip || next == .tools) {
                windows.focusNotchForTyping()
            }
        }
    }

    // MARK: - Compact Bar

    private func compactBody(lang: String) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let phase = PrayerTimeService.phase(at: ctx.date, in: viewModel.prayers)
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    if productivity.isFocusRunning {
                        Image(systemName: "timer")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tint)
                        Text(NotchProductivityService.formatTimer(productivity.remainingSeconds))
                            .foregroundStyle(.tint)
                            .fontWeight(.bold)
                            .monospacedDigit()
                    } else if let phase {
                        Text(phasePrayer(phase).name)
                            .lineLimit(1)
                            .opacity(0.88)
                        Text(phaseSubtitle(phase, now: ctx.date, compact: true, lang: lang))
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

                HStack(spacing: 5) {
                    cameraDot
                    if !productivity.shelf.isEmpty {
                        Circle().fill(.green).frame(width: 5, height: 5)
                    }
                }

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
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    windows.expanded = "notch"
                }
            }
        }
    }

    // MARK: - Expanded Multi-Section Command Center

    private func expandedBody(lang: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section tab bar
            HStack(spacing: 4) {
                ForEach(Tab.allCases) { item in
                    let active = tab == item
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { tab = item }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: item.symbol).font(.system(size: 10, weight: .semibold))
                            Text(item.rawValue).font(.system(size: 11, weight: active ? .semibold : .medium))
                            if item == .shelf && !productivity.shelf.isEmpty {
                                Text("\(productivity.shelf.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .background(.tint.opacity(0.3), in: Capsule())
                            }
                            if item == .focus && productivity.isFocusRunning {
                                Circle().fill(.tint).frame(width: 5, height: 5)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(active ? .white.opacity(0.14) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        windows.expanded = nil
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Collapse Notch")
            }

            Divider().overlay(.white.opacity(0.1))

            Group {
                switch tab {
                case .hub: hubSection(lang: lang)
                case .focus: focusSection()
                case .shelf: shelfSection()
                case .clip: clipSection()
                case .notes: notesSection()
                case .tools: toolsSection()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(height: 320)
    }

    // MARK: Tab 1 — Hub

    private func hubSection(lang: String) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let phase = PrayerTimeService.phase(at: ctx.date, in: viewModel.prayers)
            VStack(alignment: .leading, spacing: 10) {
                if let track = nowPlaying.track {
                    HStack(spacing: 12) {
                        if let art = track.artwork {
                            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08))
                                .frame(width: 40, height: 40).overlay(Image(systemName: "music.note").opacity(0.6))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            Text(track.artist).font(.system(size: 11)).opacity(0.68).lineLimit(1)
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            Button { nowPlaying.perform(.previous) } label: { Image(systemName: "backward.fill") }
                            Button { nowPlaying.perform(.toggle) } label: {
                                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").foregroundStyle(.tint)
                            }
                            Button { nowPlaying.perform(.next) } label: { Image(systemName: "forward.fill") }
                        }
                        .buttonStyle(.plain).font(.system(size: 13))
                    }
                    .padding(9)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                HStack(alignment: .top, spacing: 10) {
                    // Prayer mini card
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(phase.map { phasePrayer($0).name } ?? L10n.tr(lang, "Jadwal Sholat", "Prayer"))
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            if let phase {
                                Text(phaseSubtitle(phase, now: ctx.date, compact: true, lang: lang))
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tint).monospacedDigit()
                            }
                        }
                        HStack(spacing: 4) {
                            ForEach(viewModel.prayers) { p in
                                let isNext = phase.map { phasePrayer($0).key == p.key } ?? false
                                VStack(spacing: 2) {
                                    Text(p.name.prefix(3)).font(.system(size: 9.5)).opacity(0.7)
                                    Text(p.time.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tint).monospacedDigit()
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 5)
                                .background(.white.opacity(isNext ? 0.14 : 0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Agenda & System mini card
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.tr(lang, "Agenda & Sistem", "Agenda & System")).font(.system(size: 11.5, weight: .semibold))
                            Spacer()
                            if let w = viewModel.weather {
                                Text("\(w.temperature)°").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tint)
                            }
                        }
                        if viewModel.events.isEmpty {
                            Text(L10n.tr(lang, "Tidak ada jadwal hari ini", "Clear schedule today"))
                                .font(.system(size: 10.5)).opacity(0.55)
                        } else {
                            ForEach(viewModel.events.prefix(2)) { ev in
                                HStack(spacing: 5) {
                                    Circle().fill(Color(cgColor: ev.color)).frame(width: 6, height: 6)
                                    Text(ev.title).font(.system(size: 10.5)).lineLimit(1)
                                    Spacer()
                                    Text(ev.isAllDay ? "All day" : ev.start.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 9.5)).opacity(0.6).monospacedDigit()
                                }
                            }
                        }
                        Spacer(minLength: 2)
                        HStack(spacing: 8) {
                            Text("CPU \(stats.stats.cpu)%")
                            Text("RAM \(stats.stats.ram)%")
                            if let bat = stats.stats.battery { Text("BAT \(bat)%") }
                        }
                        .font(.system(size: 10, weight: .medium)).opacity(0.75).monospacedDigit()
                    }
                    .padding(10)
                    .frame(width: 210)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Quick multitasking footer
                HStack(spacing: 8) {
                    quickPill("Window Switcher", symbol: "macwindow.on.rectangle") {
                        windows.expanded = nil
                        windows.toggleSwitcher()
                    }
                    quickPill(productivity.isFocusRunning ? "Focus \(NotchProductivityService.formatTimer(productivity.remainingSeconds))" : "Start 25m Focus", symbol: "timer") {
                        if !productivity.isFocusRunning { productivity.toggleFocus() }
                        tab = .focus
                    }
                    quickPill("Shelf (\(productivity.shelf.count))", symbol: "tray.and.arrow.down") { tab = .shelf }
                    quickPill("Clipboard", symbol: "doc.on.clipboard") { tab = .clip }
                }
            }
        }
    }

    // MARK: Tab 2 — Focus (Pomodoro)

    private func focusSection() -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(NotchProductivityService.FocusMode.allCases) { mode in
                    let active = productivity.focusMode == mode
                    Button(mode.rawValue) { productivity.selectMode(mode) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: active ? .bold : .medium))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(active ? AnyShapeStyle(.tint.opacity(0.3)) : AnyShapeStyle(.white.opacity(0.08)), in: Capsule())
                }
                Spacer()
                Label("\(productivity.completedSessionsToday) today", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.tint)
            }

            HStack(spacing: 24) {
                Text(NotchProductivityService.formatTimer(productivity.remainingSeconds))
                    .font(.system(size: 62, weight: .ultraLight))
                    .monospacedDigit()
                    .foregroundStyle(productivity.isFocusRunning ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))

                VStack(alignment: .leading, spacing: 10) {
                    Text(productivity.focusMode.isBreak ? "Recharge Break" : "Deep Focus Sprint")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Live countdown stays visible in the collapsed Notch so you stay in flow.")
                        .font(.system(size: 11)).opacity(0.65).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button {
                            productivity.toggleFocus()
                        } label: {
                            Label(productivity.isFocusRunning ? "Pause" : "Start", systemImage: productivity.isFocusRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .background(.tint.opacity(0.35), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            productivity.resetFocus()
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(.white.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: Tab 3 — File Shelf + AirDrop

    private func shelfSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Drag files onto the Notch to park, drag out to any app, or AirDrop.")
                    .font(.system(size: 11)).opacity(0.7)
                Spacer()
                Button { productivity.pickFilesToAdd() } label: {
                    Label("Add", systemImage: "plus").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 4).background(.white.opacity(0.12), in: Capsule())
                }.buttonStyle(.plain)
                if !productivity.shelf.isEmpty {
                    Button { productivity.airDrop(productivity.shelf.map(\.url)) } label: {
                        Label("AirDrop All", systemImage: "antenna.radiowaves.left.and.right").font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 9).padding(.vertical, 4).background(.tint.opacity(0.3), in: Capsule())
                    }.buttonStyle(.plain)
                    Button("Clear") { productivity.clearShelf() }
                        .buttonStyle(.plain).font(.system(size: 11)).opacity(0.65)
                }
            }

            if productivity.shelf.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 28)).opacity(0.55)
                    Text("Drop files here").font(.system(size: 13, weight: .medium)).opacity(0.75)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5])))
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(productivity.shelf) { file in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                                    .resizable().frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(file.sizeText).font(.system(size: 10)).opacity(0.6)
                                }
                                Spacer()
                                Button { productivity.airDrop([file.url]) } label: { Image(systemName: "antenna.radiowaves.left.and.right") }
                                    .buttonStyle(.plain).help("AirDrop")
                                Button { productivity.revealFile(file) } label: { Image(systemName: "folder") }
                                    .buttonStyle(.plain).help("Reveal in Finder")
                                Button { productivity.copyToPasteboard(file.url.path) } label: { Image(systemName: "doc.on.doc") }
                                    .buttonStyle(.plain).help("Copy path")
                                Button { productivity.removeFile(file) } label: { Image(systemName: "xmark.circle.fill").opacity(0.65) }
                                    .buttonStyle(.plain).help("Remove")
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .onDrag { NSItemProvider(object: file.url as NSURL) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Tab 4 — Clipboard Manager

    private func clipSection() -> some View {
        let filtered = productivity.clipboard.filter {
            clipQuery.isEmpty || $0.text.localizedCaseInsensitiveContains(clipQuery)
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).opacity(0.6)
                    TextField("Search clipboard history…", text: $clipQuery)
                        .textFieldStyle(.plain).font(.system(size: 11.5))
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                if !productivity.clipboard.isEmpty {
                    Button("Clear") { productivity.clearUnpinnedClipboard() }
                        .buttonStyle(.plain).font(.system(size: 11)).opacity(0.7)
                }
            }

            if filtered.isEmpty {
                Text(productivity.clipboard.isEmpty ? "Copy any text — it appears here automatically." : "No matching clipboard entries.")
                    .font(.system(size: 12)).opacity(0.6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(filtered.prefix(20)) { entry in
                            HStack(spacing: 8) {
                                Button { productivity.togglePin(entry) } label: {
                                    Image(systemName: entry.pinned ? "pin.fill" : "pin")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(entry.pinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.45)))
                                }.buttonStyle(.plain).help("Pin")

                                Text(entry.text.replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 11.5)).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture { productivity.copyToPasteboard(entry.text) }

                                Menu {
                                    Button("Copy") { productivity.copyToPasteboard(entry.text) }
                                    Button("Copy Trimmed") { productivity.copyToPasteboard(NotchProductivityService.transform(entry.text, .trim)) }
                                    Button("Copy Single Line") { productivity.copyToPasteboard(NotchProductivityService.transform(entry.text, .singleLine)) }
                                    Button("Copy UPPERCASE") { productivity.copyToPasteboard(NotchProductivityService.transform(entry.text, .uppercase)) }
                                    Button("Copy lowercase") { productivity.copyToPasteboard(NotchProductivityService.transform(entry.text, .lowercase)) }
                                    Divider()
                                    Button("Delete", role: .destructive) { productivity.deleteClip(entry) }
                                } label: {
                                    Image(systemName: "wand.and.stars").font(.system(size: 11)).opacity(0.75)
                                }
                                .menuStyle(.borderlessButton).frame(width: 24)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    // MARK: Tab 5 — Notes & Reminders

    private func notesSection() -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick Scratchpad (notes.md)").font(.system(size: 11, weight: .semibold)).opacity(0.75)
                TextEditor(text: $notesStore.text)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("Apple Reminders").font(.system(size: 11, weight: .semibold)).opacity(0.75)
                HStack(spacing: 5) {
                    TextField("New reminder…", text: $newReminderTitle)
                        .textFieldStyle(.plain).font(.system(size: 11))
                        .onSubmit { addReminder() }
                    Button(action: addReminder) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        if reminders.items.isEmpty {
                            Text("No open reminders").font(.system(size: 11)).opacity(0.5).padding(.top, 8)
                        } else {
                            ForEach(reminders.items.prefix(8)) { item in
                                Button { reminders.toggle(item) } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 11)).foregroundStyle(.tint)
                                        Text(item.title).font(.system(size: 11)).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(width: 205)
        }
    }

    // MARK: Tab 6 — Tools & Bookmarks

    private func toolsSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                quickPill("Window Switcher", symbol: "macwindow.on.rectangle") {
                    windows.expanded = nil
                    windows.toggleSwitcher()
                }
                quickPill("Refresh Data", symbol: "arrow.clockwise") {
                    Task { await viewModel.refresh(force: true) }
                }
                quickPill(windows.clickThrough ? "Click-Through: ON" : "Click-Through: OFF", symbol: "cursorarrow.click.2") {
                    windows.clickThrough.toggle()
                }
            }

            Text("Quick Bookmarks").font(.system(size: 11.5, weight: .semibold)).opacity(0.8)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), spacing: 8)], spacing: 8) {
                ForEach(productivity.bookmarks) { bm in
                    HStack(spacing: 6) {
                        Button {
                            productivity.openBookmark(bm)
                            windows.expanded = nil
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: bm.symbol).font(.system(size: 11)).foregroundStyle(.tint)
                                Text(bm.title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        Button { productivity.removeBookmark(bm) } label: {
                            Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)).opacity(0.45)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            HStack(spacing: 6) {
                TextField("Name", text: $newBookmarkTitle).textFieldStyle(.plain).font(.system(size: 11))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(width: 110)
                TextField("https://…", text: $newBookmarkURL).textFieldStyle(.plain).font(.system(size: 11))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button("Add") {
                    productivity.addBookmark(title: newBookmarkTitle, url: newBookmarkURL)
                    newBookmarkTitle = ""
                    newBookmarkURL = ""
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.tint.opacity(0.3), in: Capsule())
            }
        }
    }

    // MARK: - Helpers

    private func addReminder() {
        let t = newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        reminders.add(title: t)
        newReminderTitle = ""
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var matched = false
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            matched = true
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                if let url {
                    Task { @MainActor in
                        productivity.addFiles([url])
                        tab = .shelf
                        windows.expanded = "notch"
                    }
                }
            }
        }
        return matched
    }

    private func quickPill(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.white.opacity(0.09), in: Capsule())
        }
        .buttonStyle(.plain)
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
