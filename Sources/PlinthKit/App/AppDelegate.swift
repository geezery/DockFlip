import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var onboarding: OnboardingController?
    private lazy var settingsWindow = SettingsWindowController()

    private var registry: WindowRegistry?
    private var switcher: SwitcherController?
    private var snapper: SnapController?
    private var taskbar: TaskbarController?
    private var usage: UsageTracker?
    private var cleanup: CleanupController?
    private var placement: PlacementMemory?
    private var hotkeys: HotkeyTap?
    private var hotkeysRunning = false
    private var isRelaunching = false
    private var settingsSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Perf.shared // starts the clock: the debug log covers everything from launch
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        Log.app.notice("Plinth \(version, privacy: .public) starting, macOS \(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public)")
        setUpStatusItem()
        Diagnostics.stateProvider = { [weak self] in
            guard let self else { return [] }
            var lines = self.registry?.debugSummary() ?? ["services not started"]
            lines.append("eventTap=\(self.hotkeysRunning) cleanupSuggestions=\(self.cleanup?.candidateCount() ?? 0)")
            return lines
        }
        settingsWindow.onShowSetup = { [weak self] in self?.showOnboarding() }

        if Permissions.isAccessibilityTrusted {
            startServices()
        }
        if !Permissions.isAccessibilityTrusted || !Settings.shared.onboardingCompleted {
            showOnboarding()
        }

        // ⌘Tab belongs to Plinth only while its shortcuts are on.
        settingsSubscription = Settings.shared.$shortcutsEnabled.sink { [weak self] enabled in
            Task { @MainActor in
                guard let self, self.hotkeysRunning else { return }
                NativeCommandTab.setEnabled(!enabled)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Give ⌘Tab back to macOS — unless a new Plinth instance is taking over.
        if !isRelaunching {
            NativeCommandTab.setEnabled(true)
        }
        usage?.saveNow()
        Log.app.notice("Plinth quitting")
    }

    // MARK: - Services

    private func startServices() {
        guard registry == nil else { return }

        let registry = WindowRegistry()
        registry.start()

        let switcher = SwitcherController(registry: registry)
        let snapper = SnapController(registry: registry)
        snapper.start()
        let taskbar = TaskbarController(registry: registry)
        taskbar.start()
        let usage = UsageTracker(registry: registry)
        usage.start()
        let placement = PlacementMemory(registry: registry)
        placement.start()
        let cleanup = CleanupController(registry: registry, usage: usage)

        let hotkeys = HotkeyTap()
        hotkeys.isEnabled = { Settings.shared.shortcutsEnabled }
        hotkeys.isSwitcherActive = { [weak switcher] in switcher?.isActive ?? false }
        hotkeys.handler = { [weak switcher, weak snapper, weak taskbar] command in
            switch command {
            case .switcher(let input):
                return switcher?.handle(input) ?? false
            case .snap(let key):
                return snapper?.handle(key) ?? false
            case .moveToDisplay(let key):
                return snapper?.moveToDisplay(key) ?? false
            case .taskbarItem(let index):
                return taskbar?.activateItem(at: index) ?? false
            case .showDesktop:
                taskbar?.showDesktop()
                return true
            case .newFinderWindow:
                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
                return true
            }
        }
        hotkeysRunning = hotkeys.start()
        if hotkeysRunning {
            NativeCommandTab.setEnabled(!Settings.shared.shortcutsEnabled)
        } else {
            // Right after Accessibility is granted, macOS sometimes refuses the
            // event tap until the app is restarted.
            Log.keys.error("Could not create the keyboard event tap")
        }

        self.registry = registry
        self.switcher = switcher
        self.snapper = snapper
        self.taskbar = taskbar
        self.usage = usage
        self.placement = placement
        self.cleanup = cleanup
        self.hotkeys = hotkeys
        let tapState = hotkeysRunning ? "on" : "OFF"
        Log.app.notice("Services started, event tap \(tapState, privacy: .public)")
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
            if !self.hotkeysRunning { self.relaunch() }
        }
        onboarding = controller
        controller.show()
    }

    private func relaunch() {
        isRelaunching = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.make()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Rebuilt every time the menu opens, so the status lines are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if Permissions.isAccessibilityTrusted {
            addStatus(L("Accessibility: allowed"), to: menu)
        } else {
            menu.addItem(ClosureMenuItem(L("Grant Accessibility…")) { [weak self] in self?.showOnboarding() })
        }
        if registry != nil {
            addStatus(hotkeysRunning ? L("⌘Tab: active") : L("⌘Tab: not active"), to: menu)
            addStatus(String(format: L("Windows tracked: %ld"), registry?.trackedWindowCount ?? 0), to: menu)
            if !hotkeysRunning {
                menu.addItem(ClosureMenuItem(L("Restart Plinth")) { [weak self] in self?.relaunch() })
            }
        }

        if let cleanup {
            let count = cleanup.candidateCount()
            let title = count > 0 ? String(format: L("Clean Up (%ld)…"), count) : L("Clean Up…")
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(title) { cleanup.show() })
        }

        menu.addItem(.separator())
        let settings = ClosureMenuItem(L("Settings…")) { [weak self] in self?.settingsWindow.show() }
        settings.keyEquivalent = ","
        menu.addItem(settings)

        let debug = ClosureMenuItem(L("Debug Logging")) { Settings.shared.debugLogging.toggle() }
        debug.state = Settings.shared.debugLogging ? .on : .off
        menu.addItem(debug)
        menu.addItem(ClosureMenuItem(L("Save Debug Log…")) { Diagnostics.exportLog() })

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit Plinth"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func addStatus(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }
}

/// Localized string with the English text as its key.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
