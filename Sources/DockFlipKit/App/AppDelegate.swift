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
    /// Watches Accessibility while the features run, so switching it off in System
    /// Settings gives ⌘Tab back to macOS within a second (`AccessibilityLoss`).
    private lazy var permissionWatch = AccessibilityWatch()
    private var permissionObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Perf.shared // starts the clock: the debug log covers everything from launch
        let version = AppVersion.display
        let language = AppLanguage.current
        Log.app.notice("DockFlip \(version, privacy: .public) starting, macOS \(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public), language \(language, privacy: .public)")

        statusMenu = StatusMenu(actions: StatusMenu.Actions(
            services: { [weak self] in self?.services },
            showSetup: { [weak self] in self?.showOnboarding() },
            showSettings: { [weak self] in self?.settingsWindow.show() },
            relaunch: { [weak self] in self?.relaunch() }
        ))
        Diagnostics.stateProvider = { [weak self] in self?.services?.debugLines() ?? ["services not started"] }
        settingsWindow.services = { [weak self] in self?.services }
        settingsWindow.onShowSetup = { [weak self] in self?.showOnboarding() }
        // Screen Recording allowed in System Settings often applies only after a restart.
        settingsWindow.onRelaunch = { [weak self] in self?.relaunch() }

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
        watchPermission()
    }

    /// Listens for the announcement macOS posts whenever a switch in the Accessibility
    /// list flips; `AccessibilityWatch` asks again a few times, as it does for setup.
    /// Kept for the life of the app: one observer, no timer.
    private func watchPermission() {
        guard permissionObserver == nil else { return }
        permissionWatch.check() // the answer may have changed since launch: no action for that
        permissionWatch.onChange = { [weak self] granted in self?.permissionChanged(granted) }
        permissionObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.permissionWatch.settingsChanged() }
        }
    }

    private func permissionChanged(_ granted: Bool) {
        let action = AccessibilityLoss.action(
            granted: granted, servicesStarted: services != nil, suspended: services?.suspended ?? false
        )
        switch action {
        case .none:
            break
        case .giveBackShortcuts:
            Log.app.error("Accessibility was switched off: ⌘Tab goes back to macOS, setup opens")
            services?.suspendForLostPermission()
            showOnboarding(atPermission: true)
        case .restart:
            Log.app.notice("Accessibility is back: restarting DockFlip")
            relaunch()
        }
    }

    private func showOnboarding(atPermission: Bool = false) {
        if let onboarding {
            if atPermission { onboarding.showPermissionStep() } else { onboarding.show() }
            return
        }
        let controller = OnboardingController(showSettings: { [weak self] in
            self?.settingsWindow.show()
        }) { [weak self] in
            guard let self else { return }
            self.onboarding = nil
            // Setup finished after the permission came back: the old taps are dead.
            if self.services?.suspended == true {
                self.relaunch()
                return
            }
            self.startServices()
            // Right after Accessibility is granted, macOS may refuse the key taps
            // until the app restarts.
            if self.services?.tapsRunning == false { self.relaunch() }
        }
        onboarding = controller
        if atPermission { controller.showPermissionStep() } else { controller.show() }
    }

    private func relaunch() {
        // Setup's Continue and the permission watch can both ask for it: start one copy.
        guard !isRelaunching else { return }
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
