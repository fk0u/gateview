import Foundation

/// GitHub Releases check: auto once a day from the menu bar, on demand from Settings → About.
/// (Sparkle would need a Developer ID signature; this works for an unsigned build.)
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()
    static let releasesURL = URL(string: "https://github.com/fk0u/gateview/releases/latest")!

    @Published private(set) var latest: String?

    var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var isAvailable: Bool {
        latest.map { $0.compare(current, options: .numeric) == .orderedDescending } ?? false
    }

    @discardableResult
    func check() async -> String {
        struct Release: Decodable { let tag_name: String }
        let url = URL(string: "https://api.github.com/repos/fk0u/gateview/releases/latest")!
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let tag = try? JSONDecoder().decode(Release.self, from: data).tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v "))
        else { return "No releases found" }
        latest = tag
        return isAvailable ? "Version \(tag) is available on GitHub" : "You're up to date"
    }

    /// Once a day, 60 s after launch so it never slows startup.
    func autoCheck() {
        let key = "GateView.lastUpdateCheck"
        let last = UserDefaults.standard.double(forKey: key)
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard let self, await self.check() != "No releases found" else { return }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        }
    }
}
