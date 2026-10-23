import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct GateViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(windows: delegate.windows, viewModel: delegate.viewModel, store: .shared, openSettings: delegate.openSettings)
        } label: {
            Image("MenuBarIcon") // template image: follows light/dark menu bar
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let windows = WindowManager()
    let viewModel = DashboardViewModel()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon
        UNUserNotificationCenter.current().delegate = self
        windows.show(viewModel: viewModel)

        // Turn on launch-at-login once; afterwards respect the user's choice (Settings / System Settings).
        let key = "GateView.didEnableLoginItem"
        if !UserDefaults.standard.bool(forKey: key) {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    func openSettings() {
        if settingsWindow == nil {
            let root = SettingsView(store: .shared, windows: windows) { [weak self] in
                self?.viewModel.reminders.test(theme: ThemeStore.shared.theme)
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "GateView Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 820, height: 620))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // Show banners even though GateView counts as the "active" app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}

private struct MenuContent: View {
    @ObservedObject var windows: WindowManager
    let viewModel: DashboardViewModel
    @ObservedObject var store: ThemeStore
    let openSettings: () -> Void

    var body: some View {
        Button("Settings…", action: openSettings)
            .keyboardShortcut(",")
        Divider()
        Toggle("Interactive Widgets", isOn: $store.theme.interactive)
        Toggle("Click-Through Everywhere", isOn: $windows.clickThrough)
            .keyboardShortcut("t")
        Button("Refresh") { Task { await viewModel.refresh(force: true) } }
            .keyboardShortcut("r")
        Divider()
        Button("Quit GateView") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
