/// What the menu says when another app holds some of DockFlip's shortcuts.
///
/// Rectangle's and Magnet's defaults are ⌃⌥ with the arrows, D and E: exactly
/// DockFlip's keys. Whichever app registers first gets them, and macOS never says
/// which app holds a hot key, so DockFlip names the known apps that are running.
enum ShortcutConflicts {
    struct App: Equatable {
        let bundleID: String
        let name: String
    }

    /// Window managers whose default shortcuts include DockFlip's ⌃⌥ keys.
    static let layoutApps: [App] = [
        App(bundleID: "com.knollsoft.Rectangle", name: "Rectangle"),
        App(bundleID: "com.knollsoft.Hookshot", name: "Rectangle Pro"),
        App(bundleID: "com.crowdcafe.windowmagnet", name: "Magnet"),
        App(bundleID: "com.divisiblebyzero.Spectacle", name: "Spectacle")
    ]

    /// Switchers that can hold ⌘Tab.
    static let commandTabApps: [App] = [
        App(bundleID: "com.lwouis.alt-tab-macos", name: "AltTab")
    ]

    /// The failed shortcuts other than ⌘Tab (which has its own menu line), as
    /// people type them. All nine Dock digits read as one "⌃⌥1…9".
    static func layoutShortcutNames(failed: [HotkeyCommand]) -> [String] {
        let others = failed.filter { !HotKeyRegistration.commandTab.contains($0) }
        let digits = others.filter { if case .dockItem = $0 { return true } else { return false } }
        let allDigits = digits.count == KeyCode.digits.count
        var names: [String] = []
        for command in others {
            if allDigits, case .dockItem(let index) = command {
                if index == 0 { names.append("⌃⌥1…9") }
                continue
            }
            names.append(command.shortcutName)
        }
        return names
    }

    /// The names of `apps` that are running, in the list's order.
    static func running(_ apps: [App], bundleIDs: [String]) -> [String] {
        apps.filter { bundleIDs.contains($0.bundleID) }.map(\.name)
    }
}
