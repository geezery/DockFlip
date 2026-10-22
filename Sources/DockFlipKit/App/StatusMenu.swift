import AppKit

/// DockFlip's menu bar item and its menu: status, the Window Layout cheat sheet,
/// Clean Up, Settings, language, debug logging, Quit. Rebuilt every time it
/// opens, so the status lines are always current.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    /// What the menu needs from the app.
    struct Actions {
        let services: () -> Services?
        let showSetup: () -> Void
        let showSettings: () -> Void
        let relaunch: () -> Void
    }

    private let actions: Actions
    private var statusItem: NSStatusItem?

    init(actions: Actions) {
        self.actions = actions
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.make()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let services = actions.services()

        if Permissions.isAccessibilityTrusted {
            addStatus(L("Accessibility: allowed"), to: menu)
        } else {
            menu.addItem(ClosureMenuItem(L("Grant Accessibility…"), handler: actions.showSetup))
        }
        if !Settings.shared.onboardingCompleted {
            menu.addItem(ClosureMenuItem(L("Continue Setup…"), handler: actions.showSetup))
        }
        if let services {
            addStatus(services.shortcutsActive ? L("⌘Tab: active") : L("⌘Tab: not active"), to: menu)
            addStatus(String(format: L("Windows tracked: %ld"), services.registry.trackedWindowCount), to: menu)
            if !services.tapsRunning {
                menu.addItem(ClosureMenuItem(L("Restart DockFlip"), handler: actions.relaunch))
            }

            menu.addItem(.separator())
            let layout = NSMenuItem(title: L("Window Layout"), action: nil, keyEquivalent: "")
            layout.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)
            layout.submenu = windowLayoutMenu(services)
            menu.addItem(layout)

            let count = services.cleanup.candidateCount()
            let title = count > 0 ? String(format: L("Clean Up (%ld)…"), count) : L("Clean Up…")
            menu.addItem(ClosureMenuItem(title) { services.cleanup.show() })
        }

        menu.addItem(.separator())
        let settings = ClosureMenuItem(L("Settings…"), handler: actions.showSettings)
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(languageItem())

        let debug = ClosureMenuItem(L("Debug Logging")) { Settings.shared.debugLogging.toggle() }
        debug.state = Settings.shared.debugLogging ? .on : .off
        menu.addItem(debug)
        menu.addItem(ClosureMenuItem(L("Save Debug Log…")) { Diagnostics.exportLog() })

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit DockFlip"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func addStatus(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    // MARK: - Window Layout

    /// Every keyboard action with its shortcut, as Rectangle lists them: a cheat
    /// sheet while the shortcuts are new. Clicking an item applies it to the front
    /// window. ⌃⌥ plays the Win key: Win+D is ⌃⌥D.
    private func windowLayoutMenu(_ services: Services) -> NSMenu {
        let menu = NSMenu()
        let win: NSEvent.ModifierFlags = [.control, .option]
        let left = Self.key(NSLeftArrowFunctionKey)
        let right = Self.key(NSRightArrowFunctionKey)
        let up = Self.key(NSUpArrowFunctionKey)
        let down = Self.key(NSDownArrowFunctionKey)
        let snapper = services.snapper

        func add(_ title: String, symbol: String, key: String = "", modifiers: NSEvent.ModifierFlags = [],
                 hint: String? = nil, action: @escaping () -> Void) {
            let item = ClosureMenuItem(title, handler: action)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = modifiers
            if let hint { item.subtitle = hint }
            menu.addItem(item)
        }

        add(L("Left Half"), symbol: "rectangle.lefthalf.filled", key: left, modifiers: win) { snapper.snap(to: .leftHalf) }
        add(L("Right Half"), symbol: "rectangle.righthalf.filled", key: right, modifiers: win) { snapper.snap(to: .rightHalf) }
        add(L("Maximize"), symbol: "rectangle.inset.filled", key: up, modifiers: win) { snapper.snap(to: .maximized) }
        add(L("Restore, Then Minimize"), symbol: "arrow.down.right.and.arrow.up.left", key: down, modifiers: win) {
            _ = snapper.handle(.down)
        }
        menu.addItem(.separator())
        add(L("Top Left"), symbol: "rectangle.inset.topleft.filled", hint: L("From the left half: ⌃⌥↑")) { snapper.snap(to: .topLeft) }
        add(L("Top Right"), symbol: "rectangle.inset.topright.filled", hint: L("From the right half: ⌃⌥↑")) { snapper.snap(to: .topRight) }
        add(L("Bottom Left"), symbol: "rectangle.inset.bottomleft.filled", hint: L("From the left half: ⌃⌥↓")) { snapper.snap(to: .bottomLeft) }
        add(L("Bottom Right"), symbol: "rectangle.inset.bottomright.filled", hint: L("From the right half: ⌃⌥↓")) { snapper.snap(to: .bottomRight) }
        menu.addItem(.separator())
        add(L("Move to Previous Display"), symbol: "arrow.left.to.line", key: left, modifiers: win.union(.shift)) {
            _ = snapper.moveToDisplay(.left)
        }
        add(L("Move to Next Display"), symbol: "arrow.right.to.line", key: right, modifiers: win.union(.shift)) {
            _ = snapper.moveToDisplay(.right)
        }
        menu.addItem(.separator())
        add(L("Show Desktop"), symbol: "menubar.dock.rectangle", key: "d", modifiers: win) { services.perform(.showDesktop) }
        add(L("New Finder Window"), symbol: "folder", key: "e", modifiers: win) { services.perform(.newFinderWindow) }
        menu.addItem(.separator())

        // Shortcuts that only make sense from the keyboard: listed, not clickable.
        let reminders: [(String, String)] = [
            (L("Switch Windows"), "⌘Tab"),
            (L("Open the n-th App in the Dock"), "⌃⌥1…9"),
            (L("Snap by Dragging"), L("Drag a window to an edge or corner"))
        ]
        for (title, hint) in reminders {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.subtitle = hint
            item.isEnabled = false
            menu.addItem(item)
        }
        return menu
    }

    private static func key(_ functionKey: Int) -> String {
        String(Character(UnicodeScalar(functionKey)!))
    }

    // MARK: - Language

    /// "Language" — with the English word added when another language is
    /// showing, and every language listed by its own name and its English name,
    /// so whoever picked a language they cannot read can find English again.
    private func languageItem() -> NSMenuItem {
        let english = AppLanguage.current == "en"
        let item = NSMenuItem(title: english ? "Language" : "\(L("Language")) (Language)", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Language")

        let menu = NSMenu()
        let chosen = AppLanguage.chosen
        let system = ClosureMenuItem(L("Same as macOS")) { [weak self] in self?.choose(nil) }
        system.subtitle = english ? nil : "Same as macOS"
        system.state = chosen == nil ? .on : .off
        menu.addItem(system)
        menu.addItem(.separator())
        for option in AppLanguage.all {
            let entry = ClosureMenuItem(option.nativeName) { [weak self] in self?.choose(option.code) }
            if option.nativeName != option.englishName { entry.subtitle = option.englishName }
            entry.state = chosen == option.code ? .on : .off
            menu.addItem(entry)
        }
        item.submenu = menu
        return item
    }

    /// A new language shows after a restart; DockFlip restarts at once.
    private func choose(_ code: String?) {
        guard code != AppLanguage.chosen else { return }
        AppLanguage.choose(code)
        Log.app.notice("Language set to \(code ?? "system", privacy: .public); restarting")
        actions.relaunch()
    }
}
