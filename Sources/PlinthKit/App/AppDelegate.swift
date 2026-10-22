import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var onboarding: OnboardingController?
    private var registry: WindowRegistry?
    private var switcher: SwitcherController?
    private var hotkeys: HotkeyTap?

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
        if !hotkeys.start() {
            NSLog("Plinth: could not create the keyboard event tap. Is Accessibility allowed?")
        }

        self.registry = registry
        self.switcher = switcher
        self.hotkeys = hotkeys
        rebuildMenu()
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
        }
        onboarding = controller
        controller.show()
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
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if Permissions.isAccessibilityTrusted {
            let status = NSMenuItem(title: L("Accessibility: allowed"), action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        } else {
            menu.addItem(withTitle: L("Grant Accessibility…"), action: #selector(grantAccessibility), keyEquivalent: "")
                .target = self
        }

        menu.addItem(.separator())

        let login = NSMenuItem(title: L("Launch at Login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L("Quit Plinth"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    @objc private func grantAccessibility() {
        showOnboarding()
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
        rebuildMenu()
    }
}

/// Localized string with the English text as its key.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
