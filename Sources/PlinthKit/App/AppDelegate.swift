import AppKit
import Carbon.HIToolbox
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var onboarding: OnboardingController?
    private lazy var settingsWindow = SettingsWindowController()

    private var registry: WindowRegistry?
    private var switcher: SwitcherController?
    private var snapper: SnapController?
    /// Dock mode (the default).
    private var dock: DockController?
    /// Plinth's own taskbar, when the user picked it instead of the Dock.
    private var taskbar: TaskbarController?
    private var usage: UsageTracker?
    private var cleanup: CleanupController?
    private var placement: PlacementMemory?
    private var hotKeys: GlobalHotKeys?
    private var hotkeyTap: HotkeyTap?
    /// The modifier tap that notices ⌘ being released. Needs Accessibility, and
    /// right after it is granted macOS sometimes refuses it until a restart.
    private var tapsRunning = false
    private var isRelaunching = false
    private var subscriptions: [AnyCancellable] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Perf.shared // starts the clock: the debug log covers everything from launch
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let mode = Settings.shared.useDock ? "dock" : "taskbar"
        Log.app.notice("Plinth \(version, privacy: .public) starting, macOS \(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public), mode \(mode, privacy: .public)")
        setUpStatusItem()
        Diagnostics.stateProvider = { [weak self] in
            guard let self else { return [] }
            var lines = self.registry?.debugSummary() ?? ["services not started"]
            lines.append("hotKeys=\(self.hotKeys?.registeredCount ?? 0) modifierTap=\(self.tapsRunning) secureInput=\(IsSecureEventInputEnabled()) cleanupSuggestions=\(self.cleanup?.candidateCount() ?? 0)")
            return lines
        }
        settingsWindow.onShowSetup = { [weak self] in self?.showOnboarding() }

        if Permissions.isAccessibilityTrusted {
            startServices()
        }
        if !Permissions.isAccessibilityTrusted || !Settings.shared.onboardingCompleted {
            showOnboarding()
        }

        subscriptions.append(Settings.shared.$shortcutsEnabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.applyShortcutSetting() }
        })
        // Dock mode and the taskbar are set up at launch; switching restarts Plinth.
        subscriptions.append(Settings.shared.$useDock.dropFirst().removeDuplicates().sink { [weak self] _ in
            Task { @MainActor in self?.relaunch() }
        })
    }

    /// Opening Plinth again (Finder, Spotlight, Launchpad, the Dock) brings up
    /// setup if it is unfinished, otherwise settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !Permissions.isAccessibilityTrusted || !Settings.shared.onboardingCompleted {
            showOnboarding()
        } else {
            settingsWindow.show()
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Give ⌘Tab back to macOS — unless a new Plinth instance is taking over.
        if !isRelaunching {
            NativeCommandTab.setEnabled(true)
        }
        hotKeys?.unregisterAll()
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
        if Settings.shared.useDock {
            let dock = DockController(registry: registry)
            dock.start()
            self.dock = dock
        } else {
            let taskbar = TaskbarController(registry: registry)
            taskbar.start()
            self.taskbar = taskbar
        }
        let usage = UsageTracker(registry: registry)
        usage.start()
        let placement = PlacementMemory(registry: registry)
        placement.start()
        let cleanup = CleanupController(registry: registry, usage: usage)

        // Shortcuts: Carbon hot keys start everything (they work even while an app
        // holds secure keyboard input); two event taps follow the ⌘Tab session.
        let hotKeys = GlobalHotKeys()
        hotKeys.handler = { [weak self] command in self?.perform(command) }
        let hotkeyTap = HotkeyTap()
        hotkeyTap.onCommandReleased = { [weak switcher] in _ = switcher?.handle(.commandReleased) }
        hotkeyTap.onSwitcherKey = { [weak switcher] input in switcher?.handle(input) ?? false }
        switcher.onActiveChanged = { [weak hotkeyTap] active in hotkeyTap?.setSwitcherKeysEnabled(active) }
        tapsRunning = hotkeyTap.start()
        if !tapsRunning {
            Log.keys.error("Could not create the modifier event tap")
        }

        self.registry = registry
        self.switcher = switcher
        self.snapper = snapper
        self.usage = usage
        self.placement = placement
        self.cleanup = cleanup
        self.hotKeys = hotKeys
        self.hotkeyTap = hotkeyTap
        applyShortcutSetting()
        let tapState = tapsRunning ? "on" : "OFF"
        Log.app.notice("Services started, modifier tap \(tapState, privacy: .public)")
    }

    /// ⌘Tab and the ⌃⌥ shortcuts belong to Plinth while the setting is on;
    /// otherwise macOS gets ⌘Tab back.
    private func applyShortcutSetting() {
        guard let hotKeys else { return }
        if Settings.shared.shortcutsEnabled {
            NativeCommandTab.setEnabled(false)
            hotKeys.registerAll()
        } else {
            hotKeys.unregisterAll()
            NativeCommandTab.setEnabled(true)
        }
    }

    private func perform(_ command: HotkeyCommand) {
        switch command {
        case .switcher(let input):
            _ = switcher?.handle(input)
        case .snap(let key):
            _ = snapper?.handle(key)
        case .moveToDisplay(let key):
            _ = snapper?.moveToDisplay(key)
        case .taskbarItem(let index):
            if let dock {
                _ = dock.activateItem(at: index)
            } else {
                _ = taskbar?.activateItem(at: index)
            }
        case .showDesktop:
            if let taskbar { taskbar.showDesktop() } else { ShowDesktop.toggle() }
        case .newFinderWindow:
            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
        }
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
            if !self.tapsRunning { self.relaunch() }
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
        if !Settings.shared.onboardingCompleted {
            menu.addItem(ClosureMenuItem(L("Continue Setup…")) { [weak self] in self?.showOnboarding() })
        }
        if registry != nil {
            let shortcutsOn = Settings.shared.shortcutsEnabled && (hotKeys?.registeredCount ?? 0) > 0
            addStatus(shortcutsOn && tapsRunning ? L("⌘Tab: active") : L("⌘Tab: not active"), to: menu)
            addStatus(String(format: L("Windows tracked: %ld"), registry?.trackedWindowCount ?? 0), to: menu)
            if !tapsRunning {
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
