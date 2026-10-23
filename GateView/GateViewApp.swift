import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct GateViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(windows: delegate.windows, viewModel: delegate.viewModel, store: ThemeStore.shared, openSettings: delegate.openSettings)
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

        // Turn on launch-at-login once; afterwards respect the user's choice (menu / System Settings).
        let key = "GateView.didEnableLoginItem"
        if !UserDefaults.standard.bool(forKey: key) {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: .shared)))
            window.title = "GateView Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
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
    @AppStorage(ReminderMode.storageKey) private var reminder = ReminderMode.off.rawValue

    var body: some View {
        Toggle("Click-Through", isOn: $windows.clickThrough)
            .keyboardShortcut("t")
        Menu("Widgets") {
            Toggle("Weather", isOn: $store.theme.showWeather)
            Toggle("Agenda", isOn: $store.theme.showAgenda)
            Toggle("Now Playing", isOn: $store.theme.showNowPlaying)
            Toggle("System Stats", isOn: $store.theme.showStats)
        }
        Menu("Prayer Reminder") {
            Picker("Prayer Reminder", selection: Binding(get: { reminder }, set: { mode in
                reminder = mode
                Task { await viewModel.rescheduleReminders() }
            })) {
                ForEach(ReminderMode.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button("Test Reminder") { viewModel.reminders.test() }
        }
        Button("Settings…", action: openSettings)
            .keyboardShortcut(",")
        Divider()
        Toggle("Launch at Login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { on in
            try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }))
        Button("Refresh") { Task { await viewModel.refresh(force: true) } }
            .keyboardShortcut("r")
        Divider()
        Button("Quit GateView") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
