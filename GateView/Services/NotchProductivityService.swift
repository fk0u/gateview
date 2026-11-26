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

    init() {
        loadBookmarks()
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
}
