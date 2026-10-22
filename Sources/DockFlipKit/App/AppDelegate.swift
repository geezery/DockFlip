import AppKit
import Combine

/// App lifecycle: starts the features once Accessibility is allowed, shows setup
/// when needed, restarts DockFlip when asked. The features themselves live in
/// `Services`; the menu bar item in `StatusMenu`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: Services?
    private var statusMenu: StatusMenu?
    private var onboarding: OnboardingController?
    private lazy var settingsWindow = SettingsWindowController()
    /// A new DockFlip instance is taking over (restart): leave ⌘Tab to it.
    private var isRelaunching = false
    private var subscriptions: [AnyCancellable] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Perf.shared // starts the clock: the debug log covers everything from launch
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let language = AppLanguage.current
        Log.app.notice("DockFlip \(version, privacy: .public) starting, macOS \(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public), language \(language, privacy: .public)")

        statusMenu = StatusMenu(actions: StatusMenu.Actions(
            services: { [weak self] in self?.services },
            showSetup: { [weak self] in self?.showOnboarding() },
            showSettings: { [weak self] in self?.settingsWindow.show() },
            relaunch: { [weak self] in self?.relaunch() }
        ))
        Diagnostics.stateProvider = { [weak self] in self?.services?.debugLines() ?? ["services not started"] }
        settingsWindow.onShowSetup = { [weak self] in self?.showOnboarding() }

        if Permissions.isAccessibilityTrusted {
            startServices()
        }
        if !Permissions.isAccessibilityTrusted || !Settings.shared.onboardingCompleted {
            showOnboarding()
        }
        subscriptions.append(Settings.shared.$shortcutsEnabled.dropFirst().sink { [weak self] _ in
            // @Published fires before the value changes: act on the next turn.
            Task { @MainActor in self?.services?.applyShortcutSetting() }
        })
    }

    /// Opening DockFlip again (Finder, Spotlight, Launchpad) brings up setup if it
    /// is unfinished, otherwise settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !Permissions.isAccessibilityTrusted || !Settings.shared.onboardingCompleted {
            showOnboarding()
        } else {
            settingsWindow.show()
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        services?.willTerminate(handingOver: isRelaunching)
        Log.app.notice("DockFlip quitting")
    }

    private func startServices() {
        guard services == nil else { return }
        let services = Services()
        self.services = services
        let taps = services.tapsRunning ? "on" : "OFF"
        Log.app.notice("Services started, key taps \(taps, privacy: .public)")
    }

    private func showOnboarding() {
        if let onboarding {
            onboarding.show()
            return
        }
        let controller = OnboardingController { [weak self] in
            guard let self else { return }
            self.onboarding = nil
            self.startServices()
            // Right after Accessibility is granted, macOS may refuse the key taps
            // until the app restarts.
            if self.services?.tapsRunning == false { self.relaunch() }
        }
        onboarding = controller
        controller.show()
    }

    private func relaunch() {
        isRelaunching = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        // The app delegate lives as long as the app, so capturing it strongly is fine.
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { app, error in
            let started = app != nil && error == nil
            Task { @MainActor in
                guard started else {
                    // Nothing takes over: stay, and keep ⌘Tab working.
                    self.isRelaunching = false
                    Log.app.error("Restart failed; DockFlip keeps running")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}
