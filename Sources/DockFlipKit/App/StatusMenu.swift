import AppKit

/// DockFlip's menu bar item and its menu: status, the Window Layout cheat sheet,
/// Clean Up, Settings, language, debug logging, sharing, Quit. Rebuilt every time it
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

        // Which build is running, so a bug report can say whether it has a fix.
        addStatus("DockFlip \(AppVersion.display)", to: menu)
        if Permissions.isAccessibilityTrusted {
            addStatus(L("Accessibility: allowed"), to: menu)
        } else {
            menu.addItem(ClosureMenuItem(L("Grant Accessibility…"), handler: actions.showSetup))
        }
        if !Settings.shared.onboardingCompleted {
            menu.addItem(ClosureMenuItem(L("Continue Setup…"), handler: actions.showSetup))
        }
        addEdgeTilingWarning(to: menu)
        addScreenRecordingWarning(to: menu)
        if let services {
            let commandTab = addStatus(commandTabStatus(services), to: menu)
            if services.commandTabHeldElsewhere,
               let app = ShortcutConflicts.running(ShortcutConflicts.commandTabApps, bundleIDs: Self.runningBundleIDs()).first {
                commandTab.subtitle = String(format: L("Probably %@"), app)
            }
            addLayoutShortcutConflict(services, to: menu)
            addUnavailableFeatures(services, to: menu)
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
        let share = ClosureMenuItem(L("Tell a Friend…")) { [weak self] in Sharing.tellAFriend(from: self?.statusItem?.button) }
        share.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        menu.addItem(share)
        let coffee = ClosureMenuItem(L("Buy DockFlip a Coffee…")) { Sharing.buyACoffee() }
        coffee.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: nil)
        menu.addItem(coffee)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit DockFlip"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @discardableResult
    private func addStatus(_ title: String, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        return item
    }

    /// Says why ⌘Tab isn't DockFlip's when another app (AltTab) holds it: then
    /// ⌘Tab still opens macOS's own switcher, and quitting that app is the fix.
    private func commandTabStatus(_ services: Services) -> String {
        if services.shortcutsActive { return L("⌘Tab: active") }
        return services.commandTabHeldElsewhere ? L("⌘Tab: used by another app") : L("⌘Tab: not active")
    }

    /// Names the ⌃⌥ shortcuts another app (Rectangle, Magnet) holds: otherwise ⌃⌥←
    /// does that app's thing, or nothing, and snapping just looks broken. macOS
    /// doesn't say which app holds a key, so the known ones that run are named.
    /// Clicking asks for the shortcuts again, once the other app has let go.
    private func addLayoutShortcutConflict(_ services: Services, to menu: NSMenu) {
        let held = services.layoutShortcutsHeldElsewhere
        guard !held.isEmpty else { return }
        let item = ClosureMenuItem(String(format: L("%@: used by another app"), held.joined(separator: " "))) {
            Log.keys.notice("Shortcuts asked for again from the menu")
            services.applyShortcutSetting()
        }
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        let apps = ShortcutConflicts.running(ShortcutConflicts.layoutApps, bundleIDs: Self.runningBundleIDs())
        item.subtitle = apps.isEmpty
            ? L("Quit the app that uses them, then click to try again.")
            : String(format: L("Probably %@. Quit it or change its shortcuts, then click to try again."),
                     apps.joined(separator: ", "))
        menu.addItem(item)
    }

    private static func runningBundleIDs() -> [String] {
        NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
    }

    /// A new macOS can break a private call or the Dock hook without a crash or a
    /// word, and then a feature just "doesn't work". One line per feature lost,
    /// read from the self-check on every open; the debug log says more.
    private func addUnavailableFeatures(_ services: Services, to menu: NSMenu) {
        let features = UnavailableFeature.list(SelfCheck.current,
                                               accessibilityAllowed: Permissions.isAccessibilityTrusted,
                                               commandTabSwitchFound: NativeCommandTab.isAvailable,
                                               ownsCommandTab: services.shortcutsActive)
        for item in Self.unavailableItems(features) {
            menu.addItem(item)
        }
    }

    /// Status lines like "⌘Tab: not active", not buttons: no click brings a macOS
    /// call back. The triangle marks them as the menu's other warnings are marked.
    static func unavailableItems(_ features: [UnavailableFeature]) -> [NSMenuItem] {
        features.map { feature in
            let item = NSMenuItem(title: unavailableTitle(feature), action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            item.isEnabled = false
            return item
        }
    }

    static func unavailableTitle(_ feature: UnavailableFeature) -> String {
        switch feature {
        case .commandTabSwitchOff: return L("Turning off macOS's own ⌘Tab: not available on this macOS version")
        case .windowTracking: return L("Window tracking: not available on this macOS version")
        case .otherSpaces: return L("Windows on other Spaces: not available on this macOS version")
        case .dockLists: return L("Dock lists: not available on this macOS version")
        }
    }

    /// macOS's own edge tiling can come back on after setup turned it off (System
    /// Settings, a macOS update), and then a dragged window snaps twice. The menu
    /// is rebuilt on every open, so the item goes away once tiling is off.
    private func addEdgeTilingWarning(to menu: NSMenu) {
        guard NativeEdgeTiling.isOn else { return }
        let item = ClosureMenuItem(L("Turn Off macOS Edge Tiling")) {
            Log.app.notice("macOS edge tiling turned off from the menu")
            NativeEdgeTiling.turnOff()
        }
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        item.subtitle = L("Windows snap twice when dragged to an edge")
        menu.addItem(item)
    }

    /// Thumbnails switched on but Screen Recording not allowed (a denied prompt, or
    /// the restart macOS wants after allowing it): the Dock lists just show no
    /// pictures, and only Settings said why, to someone who never opens it again.
    /// Read on every open, like the rest of the menu; no timer.
    private func addScreenRecordingWarning(to menu: NSMenu) {
        let access = ThumbnailAccess(enabled: Settings.shared.previewsEnabled,
                                     screenRecordingAllowed: CGPreflightScreenCaptureAccess())
        if let item = Self.screenRecordingWarning(access, openSettings: actions.showSettings) {
            menu.addItem(item)
        }
    }

    /// The warning item for `access`, or nil when thumbnails are off or shown.
    /// It opens Settings, whose warning row offers System Settings and a restart.
    static func screenRecordingWarning(_ access: ThumbnailAccess, openSettings: @escaping () -> Void) -> NSMenuItem? {
        guard access == .waitingForPermission else { return nil }
        let item = ClosureMenuItem(L("Screen Recording is not allowed yet"), handler: openSettings)
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        item.subtitle = L("Window thumbnails are not shown")
        return item
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
