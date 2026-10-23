import Foundation

/// One plain-text note at ~/.config/gateview/notes.md, live-reloaded when edited elsewhere.
@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()
    static let url = ThemeStore.url.deletingLastPathComponent().appendingPathComponent("notes.md")

    @Published var text: String {
        didSet { if text != oldValue { save() } }
    }

    private var watcher: DispatchSourceFileSystemObject?

    private init() {
        text = (try? String(contentsOf: Self.url, encoding: .utf8)) ?? ""
        if !FileManager.default.fileExists(atPath: Self.url.path) { save() }
        watch()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: Self.url, atomically: true, encoding: .utf8)
    }

    /// Same pattern as ThemeStore: atomic saves replace the file, so re-open after every event.
    private func watch() {
        watcher?.cancel()
        let fd = open(Self.url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if let fresh = try? String(contentsOf: Self.url, encoding: .utf8), fresh != self.text { self.text = fresh }
                self.watch()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}
