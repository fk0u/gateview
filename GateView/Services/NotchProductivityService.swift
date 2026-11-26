import AppKit
import Foundation
import UserNotifications

struct ClipboardEntry: Identifiable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    var pinned: Bool

    init(id: UUID = UUID(), text: String, date: Date = .now, pinned: Bool = false) {
        self.id = id
        self.text = text
        self.date = date
        self.pinned = pinned
    }
}

struct ShelfFile: Identifiable, Equatable {
    let url: URL
    let name: String
    let sizeText: String
    var id: URL { url }
}

struct QuickBookmark: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: String
    var symbol: String
}

struct QuickTodo: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var done: Bool = false
}

struct LrcLine: Identifiable, Equatable {
    let time: Double
    let text: String
    var id: Double { time }
}

struct NotchToast: Equatable {
    let symbol: String
    let title: String
    let detail: String
    let tintHex: String
}

/// Powers the multi-section Notch Command Center:
/// 1) Deep-Work Pomodoro Timer
/// 2) Clipboard History Manager (with Pin, Search, Text Transforms)
/// 3) Drag-and-Drop File Shelf + Instant AirDrop
/// 4) Instant Quick Bookmarks
@MainActor
final class NotchProductivityService: ObservableObject {
    // MARK: Pomodoro Focus Timer
    enum FocusMode: String, CaseIterable, Identifiable {
        case focus25 = "25m"
        case deep50 = "50m"
        case break5 = "5m"
        case break15 = "15m"

        var id: String { rawValue }
        var seconds: Int {
            switch self {
            case .focus25: return 25 * 60
            case .deep50: return 50 * 60
            case .break5: return 5 * 60
            case .break15: return 15 * 60
            }
        }
        var isBreak: Bool { self == .break5 || self == .break15 }
    }

    @Published var focusMode: FocusMode = .focus25
    @Published private(set) var remainingSeconds: Int = 25 * 60
    @Published private(set) var isFocusRunning = false
    @Published private(set) var completedSessionsToday = 0

    // MARK: Live Activity Toast (Charging, Caps Lock, Water, Clipboard)
    @Published private(set) var activeToast: NotchToast?
    private var toastTask: Task<Void, Never>?

    // MARK: Synced Lyrics (LRCLIB, free & keyless)
    @Published private(set) var lyrics: [LrcLine] = []
    @Published private(set) var lyricsLoading = false
    @Published private(set) var lyricsTrackKey = ""
    private var lyricsCache: [String: [LrcLine]] = [:]

    // MARK: Water Hydration Tracker
    @Published var waterGoalML: Int = 2000 { didSet { saveWater() } }
    @Published var waterCupML: Int = 250 { didSet { saveWater() } }
    @Published private(set) var waterTodayML: Int = 0
    @Published private(set) var waterHourly: [Int: Int] = [:]
    private var waterDayKey: String = ""

    // MARK: Local To-Do List
    @Published var todos: [QuickTodo] = [] { didSet { saveTodos() } }

    // MARK: Clipboard History
    @Published private(set) var clipboard: [ClipboardEntry] = []
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let maxUnpinnedClip = 30

    // MARK: File Shelf
    @Published private(set) var shelf: [ShelfFile] = []

    // MARK: Quick Bookmarks
    @Published var bookmarks: [QuickBookmark] = [] {
        didSet { saveBookmarks() }
    }

    private var focusTask: Task<Void, Never>?
    private var clipTask: Task<Void, Never>?
    private let bookmarksKey = "GateView.quickBookmarks"
    private let todosKey = "GateView.quickTodos"
    private let waterKey = "GateView.waterState"

    init() {
        loadBookmarks()
        loadTodos()
        loadWater()
    }

    func start() {
        guard clipTask == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        clipTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let self, !Task.isCancelled else { return }
                self.pollClipboard()
            }
        }
    }

    func stop() {
        clipTask?.cancel()
        clipTask = nil
        focusTask?.cancel()
        focusTask = nil
        isFocusRunning = false
    }

    // MARK: - Pomodoro Actions

    func selectMode(_ mode: FocusMode) {
        focusTask?.cancel()
        focusTask = nil
        isFocusRunning = false
        focusMode = mode
        remainingSeconds = mode.seconds
    }

    func toggleFocus() {
        if isFocusRunning {
            focusTask?.cancel()
            focusTask = nil
            isFocusRunning = false
        } else {
            if remainingSeconds <= 0 { remainingSeconds = focusMode.seconds }
            isFocusRunning = true
            focusTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let self, !Task.isCancelled else { return }
                    if self.remainingSeconds > 1 {
                        self.remainingSeconds -= 1
                    } else {
                        self.remainingSeconds = 0
                        self.isFocusRunning = false
                        self.focusTask = nil
                        self.finishSession()
                        return
                    }
                }
            }
        }
    }

    func resetFocus() {
        focusTask?.cancel()
        focusTask = nil
        isFocusRunning = false
        remainingSeconds = focusMode.seconds
    }

    private func finishSession() {
        if !focusMode.isBreak { completedSessionsToday += 1 }
        NSSound(named: "Glass")?.play()
        let content = UNMutableNotificationContent()
        content.title = focusMode.isBreak ? "Break Complete" : "Focus Session Complete"
        content.body = focusMode.isBreak
            ? "Ready for your next deep-work sprint."
            : "Great work! \(completedSessionsToday) session(s) completed today."
        let req = UNNotificationRequest(identifier: "gateview.focus.\(UUID().uuidString)", content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(req) }
    }

    nonisolated static func formatTimer(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: - Clipboard Actions

    private func pollClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let raw = pb.string(forType: .string) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordClipboard(raw)
    }

    func recordClipboard(_ text: String) {
        clipboard = Self.insertClipboard(text, into: clipboard, maxUnpinned: maxUnpinnedClip)
    }

    func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChangeCount = pb.changeCount
        recordClipboard(text)
    }

    func togglePin(_ entry: ClipboardEntry) {
        guard let i = clipboard.firstIndex(where: { $0.id == entry.id }) else { return }
        clipboard[i].pinned.toggle()
        clipboard.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.date > b.date
        }
    }

    func deleteClip(_ entry: ClipboardEntry) {
        clipboard.removeAll { $0.id == entry.id }
    }

    func clearUnpinnedClipboard() {
        clipboard.removeAll { !$0.pinned }
    }

    enum TextTransform { case trim, singleLine, uppercase, lowercase }

    nonisolated static func transform(_ text: String, _ kind: TextTransform) -> String {
        switch kind {
        case .trim: return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .singleLine: return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        }
    }

    nonisolated static func insertClipboard(_ text: String, into existing: [ClipboardEntry], maxUnpinned: Int = 30) -> [ClipboardEntry] {
        var list = existing
        let wasPinned = list.first(where: { $0.text == text })?.pinned ?? false
        list.removeAll { $0.text == text }
        list.insert(ClipboardEntry(text: text, date: .now, pinned: wasPinned), at: 0)
        list.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.date > b.date
        }
        let pinned = list.filter(\.pinned)
        let unpinned = Array(list.filter { !$0.pinned }.prefix(maxUnpinned))
        return pinned + unpinned
    }

    // MARK: - File Shelf Actions

    func addFiles(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            guard !shelf.contains(where: { $0.url == url }) else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            shelf.append(ShelfFile(url: url, name: url.lastPathComponent, sizeText: Self.formatBytes(size)))
        }
    }

    func pickFilesToAdd() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func removeFile(_ file: ShelfFile) {
        shelf.removeAll { $0.url == file.url }
    }

    func clearShelf() {
        shelf.removeAll()
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    func revealFile(_ file: ShelfFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    nonisolated static func formatBytes(_ bytes: Int) -> String {
        guard bytes > 0 else { return "Folder" }
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var idx = 0
        while value >= 1024 && idx < units.count - 1 {
            value /= 1024
            idx += 1
        }
        return idx == 0 ? "\(bytes) B" : String(format: "%.1f %@", value, units[idx])
    }

    // MARK: - Quick Bookmarks

    private func loadBookmarks() {
        if let data = UserDefaults.standard.data(forKey: bookmarksKey),
           let decoded = try? JSONDecoder().decode([QuickBookmark].self, from: data),
           !decoded.isEmpty {
            bookmarks = decoded
            return
        }
        bookmarks = [
            QuickBookmark(title: "GitHub", url: "https://github.com", symbol: "chevron.left.forwardslash.chevron.right"),
            QuickBookmark(title: "Gmail", url: "https://mail.google.com", symbol: "envelope.fill"),
            QuickBookmark(title: "Calendar", url: "https://calendar.google.com", symbol: "calendar"),
            QuickBookmark(title: "Localhost", url: "http://localhost:3000", symbol: "terminal.fill"),
        ]
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }

    func addBookmark(title: String, url: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanURL.isEmpty else { return }
        if !cleanURL.contains("://") { cleanURL = "https://" + cleanURL }
        bookmarks.append(QuickBookmark(title: cleanTitle, url: cleanURL, symbol: "globe"))
    }

    func removeBookmark(_ b: QuickBookmark) {
        bookmarks.removeAll { $0.id == b.id }
    }

    func openBookmark(_ b: QuickBookmark) {
        if let url = URL(string: b.url) { NSWorkspace.shared.open(url) }
    }

    // MARK: - Live Activity Toast

    func showToast(symbol: String, title: String, detail: String = "", tintHex: String = "#FFC56B", duration: Double = 3.0) {
        toastTask?.cancel()
        activeToast = NotchToast(symbol: symbol, title: title, detail: detail, tintHex: tintHex)
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.activeToast = nil
        }
    }

    // MARK: - Synced Lyrics (LRCLIB)

    func loadLyrics(title: String, artist: String) async {
        let key = "\(title)|\(artist)"
        guard !title.isEmpty, key != lyricsTrackKey else { return }
        lyricsTrackKey = key
        if let cached = lyricsCache[key] {
            lyrics = cached
            return
        }
        lyrics = []
        lyricsLoading = true
        defer { lyricsLoading = false }

        var comps = URLComponents(string: "https://lrclib.net/api/get")
        comps?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = comps?.url,
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200
        else { return }

        struct LrcResponse: Decodable { let syncedLyrics: String?; let plainLyrics: String? }
        guard let decoded = try? JSONDecoder().decode(LrcResponse.self, from: data) else { return }
        let parsed: [LrcLine]
        if let synced = decoded.syncedLyrics, !synced.isEmpty {
            parsed = Self.parseLRC(synced)
        } else if let plain = decoded.plainLyrics, !plain.isEmpty {
            parsed = plain.split(separator: "\n").enumerated().map { LrcLine(time: Double($0.offset) * -1 - 1, text: String($0.element)) }
        } else {
            parsed = []
        }
        if lyricsTrackKey == key {
            lyrics = parsed
            lyricsCache[key] = parsed
        }
    }

    nonisolated static func parseLRC(_ raw: String) -> [LrcLine] {
        var out: [LrcLine] = []
        for line in raw.split(separator: "\n") {
            let s = String(line)
            guard s.hasPrefix("["), let close = s.firstIndex(of: "]") else { continue }
            let stamp = s[s.index(after: s.startIndex)..<close]
            let parts = stamp.split(separator: ":")
            guard parts.count == 2, let m = Double(parts[0]), let sec = Double(parts[1]) else { continue }
            let text = s[s.index(after: close)...].trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            out.append(LrcLine(time: m * 60 + sec, text: text))
        }
        return out.sorted { $0.time < $1.time }
    }

    nonisolated static func activeLyricIndex(at elapsed: Double, in lines: [LrcLine]) -> Int? {
        guard !lines.isEmpty, lines[0].time >= 0 else { return nil }
        return lines.lastIndex { $0.time <= elapsed + 0.25 }
    }

    // MARK: - Water Hydration Tracker

    private struct WaterDisk: Codable {
        var dayKey: String
        var goalML: Int
        var cupML: Int
        var todayML: Int
        var hourly: [Int: Int]
    }

    func drink(_ ml: Int? = nil) {
        ensureWaterToday()
        let amount = max(50, ml ?? waterCupML)
        waterTodayML += amount
        let hour = Calendar.current.component(.hour, from: .now)
        waterHourly[hour, default: 0] += amount
        saveWater()
        let pct = min(100, Int(Double(waterTodayML) / Double(max(waterGoalML, 1)) * 100))
        showToast(symbol: "drop.fill", title: "+\(amount) ml", detail: "\(pct)% of goal", tintHex: "#5AC8FA", duration: 2.5)
    }

    func resetWater() {
        waterDayKey = Self.todayKey()
        waterTodayML = 0
        waterHourly = [:]
        saveWater()
    }

    private func ensureWaterToday() {
        let today = Self.todayKey()
        if waterDayKey != today {
            waterDayKey = today
            waterTodayML = 0
            waterHourly = [:]
        }
    }

    private func loadWater() {
        let today = Self.todayKey()
        if let data = UserDefaults.standard.data(forKey: waterKey),
           let disk = try? JSONDecoder().decode(WaterDisk.self, from: data) {
            waterGoalML = max(500, disk.goalML)
            waterCupML = max(50, disk.cupML)
            if disk.dayKey == today {
                waterDayKey = disk.dayKey
                waterTodayML = disk.todayML
                waterHourly = disk.hourly
                return
            }
        }
        waterDayKey = today
        waterTodayML = 0
        waterHourly = [:]
    }

    private func saveWater() {
        let disk = WaterDisk(dayKey: waterDayKey.isEmpty ? Self.todayKey() : waterDayKey,
                             goalML: waterGoalML, cupML: waterCupML, todayML: waterTodayML, hourly: waterHourly)
        if let data = try? JSONEncoder().encode(disk) {
            UserDefaults.standard.set(data, forKey: waterKey)
        }
    }

    private static func todayKey() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    // MARK: - Local To-Do List

    var todoDoneCount: Int { todos.filter(\.done).count }

    func addTodo(_ raw: String) {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        todos.insert(QuickTodo(title: title, done: false), at: 0)
    }

    func toggleTodo(_ item: QuickTodo) {
        guard let i = todos.firstIndex(where: { $0.id == item.id }) else { return }
        todos[i].done.toggle()
    }

    func deleteTodo(_ item: QuickTodo) {
        todos.removeAll { $0.id == item.id }
    }

    private func loadTodos() {
        if let data = UserDefaults.standard.data(forKey: todosKey),
           let decoded = try? JSONDecoder().decode([QuickTodo].self, from: data) {
            todos = decoded
        }
    }

    private func saveTodos() {
        if let data = try? JSONEncoder().encode(todos) {
            UserDefaults.standard.set(data, forKey: todosKey)
        }
    }
}
