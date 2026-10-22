import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var onboarding: OnboardingController?
    private var registry: WindowRegistry?
    private var switcher: SwitcherController?
    private var hotkeys: HotkeyTap?
    private var hotkeysRunning = false
    private var isRelaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        if Permissions.isAccessibilityTrusted {
            startServices()
        } else {
            showOnboarding()
        }
    }

    // MARK: - Services

    private func startServices() {
        guard registry == nil else { return }

        let registry = WindowRegistry()
        registry.start()

        let switcher = SwitcherController(registry: registry)

        let hotkeys = HotkeyTap()
        hotkeys.handler = { [weak switcher] input in
            switcher?.handle(input) ?? false
        }
        hotkeys.isActive = { [weak switcher] in
            switcher?.isActive ?? false
        }
        hotkeysRunning = hotkeys.start()
        if hotkeysRunning {
            NativeCommandTab.setEnabled(false)
        } else {
            // Right after Accessibility is granted, macOS sometimes refuses the
            // event tap until the app is restarted.
            NSLog("Plinth: could not create the keyboard event tap.")
        }

        self.registry = registry
        self.switcher = switcher
        self.hotkeys = hotkeys
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

    func applicationWillTerminate(_ notification: Notification) {
        // Give ⌘Tab back to macOS — unless a new Plinth instance is taking over.
        if !isRelaunching {
            NativeCommandTab.setEnabled(true)
        }
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
        if let image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Plinth") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "P"
        }
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
            let grant = NSMenuItem(title: L("Grant Accessibility…"), action: #selector(grantAccessibility), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
        }

        if registry != nil {
            addStatus(hotkeysRunning ? L("⌘Tab: active") : L("⌘Tab: not active"), to: menu)
            addStatus(String(format: L("Windows tracked: %ld"), registry?.trackedWindowCount ?? 0), to: menu)
        }
        if registry != nil && !hotkeysRunning {
            let restart = NSMenuItem(title: L("Restart Plinth"), action: #selector(restartPlinth), keyEquivalent: "")
            restart.target = self
            menu.addItem(restart)
        }

        menu.addItem(.separator())

        let login = NSMenuItem(title: L("Launch at Login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit Plinth"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func addStatus(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @objc private func grantAccessibility() {
        showOnboarding()
    }

    @objc private func restartPlinth() {
        relaunch()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Plinth: launch at login change failed: \(error.localizedDescription)")
        }
    }
}

/// Localized string with the English text as its key.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
