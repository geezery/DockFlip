import AppKit

/// Shows DockFlip's own windows (setup, settings, clean up) so they can always be found.
///
/// DockFlip is normally an accessory app: no Dock icon, not in app switching. A
/// window of such an app that falls behind others is nearly impossible to find.
/// So while any of these windows is open, DockFlip becomes a regular app with a
/// Dock icon and a menu, and goes back to the menu bar when the last one closes.
/// `orderFrontRegardless` also puts the window in front when macOS 14+ refuses
/// to activate an app started from Terminal.
@MainActor
enum WindowPresenter {
    private static var watched = Set<ObjectIdentifier>()

    static func bringToFront(_ window: NSWindow) {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            installMainMenu()
        }
        let id = ObjectIdentifier(window)
        if !watched.contains(id) {
            watched.insert(id)
            _ = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    returnToMenuBarIfIdle()
                }
            }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func returnToMenuBarIfIdle() {
        let open = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
        if !open { NSApp.setActivationPolicy(.accessory) }
    }

    /// The menu shown while DockFlip is a regular app: Close Window, Quit, and Edit for text fields.
    private static func installMainMenu() {
        guard NSApp.mainMenu == nil else { return }
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: L("Quit DockFlip"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L("File"))
        fileMenu.addItem(NSMenuItem(title: L("Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L("Edit"))
        editMenu.addItem(NSMenuItem(title: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
