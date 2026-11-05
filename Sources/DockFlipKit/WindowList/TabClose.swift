import AppKit
import ApplicationServices

/// A button inside a tab, as the close-button rule sees it. Its names are never logged.
struct TabButtonInfo: Equatable, Sendable {
    let subrole: String?
    /// The button's identifier, description and title, as the browser gives them.
    let names: [String]
}

/// Which button inside a tab closes it. Pure, unit-tested.
enum TabCloseButton {
    /// A close-button subrole first (Finder, Terminal), then a name with "close"
    /// in it (browsers that name their buttons in English), else the tab's only
    /// button: a tab has one button, its ×, unless it also plays sound.
    static func pick(_ buttons: [TabButtonInfo]) -> Int? {
        if let index = buttons.firstIndex(where: { $0.subrole == kAXCloseButtonSubrole }) {
            return index
        }
        if let index = buttons.firstIndex(where: { button in
            button.names.contains { $0.range(of: "close", options: .caseInsensitive) != nil }
        }) {
            return index
        }
        return buttons.count == 1 ? 0 : nil
    }
}

/// The menu item that closes a tab: ⌘W with no other modifier, in every
/// browser, Finder and Terminal, in every language. Pure, unit-tested.
enum CloseTabShortcut {
    static func matches(cmdChar: String?, modifiers: Int?) -> Bool {
        // kAXMenuItemModifierNone (0) means ⌘ alone.
        cmdChar?.uppercased() == "W" && modifiers == 0
    }
}

/// Closes a browser tab from the Dock list through Accessibility, so the browser
/// stays where it is and DockFlip stays inactive. The browser may still ask
/// first (a page with unsent text), as it would anyway.
///
/// Browsers differ in what they show Accessibility. Chrome and Firefox give
/// each tab a × button, but hide it on narrow tabs; Safari draws its × only
/// under the mouse. So: press the tab's × when there is one; otherwise select
/// the tab and press the × it now shows, or the app's own "Close Tab" (⌘W) menu
/// item. Each step is checked by asking whether the tab still exists.
enum TabClose {
    /// What the tab shows Accessibility, for the log: roles, subroles, actions
    /// and counts only, never a name or a title.
    static func describe(_ tab: AXUIElement) -> String {
        let actions = actionNames(of: tab).joined(separator: ",")
        var parts: [String] = []
        var level = tab.elements(kAXChildrenAttribute)
        for depth in 1...2 {
            let roles = level.map { child -> String in
                let role = child.string(kAXRoleAttribute) ?? "?"
                return child.string(kAXSubroleAttribute).map { "\(role)/\($0)" } ?? role
            }
            parts.append("L\(depth)[\(roles.joined(separator: " "))]")
            level = level.flatMap { $0.elements(kAXChildrenAttribute) }
        }
        return "actions[\(actions)] " + parts.joined(separator: " ")
    }

    private static func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    /// The tab's close button, among its buttons up to two levels down.
    static func closeButton(of tab: AXUIElement) -> AXUIElement? {
        var buttons: [(element: AXUIElement, info: TabButtonInfo)] = []
        var level = tab.elements(kAXChildrenAttribute)
        for _ in 0..<2 {
            for child in level where child.string(kAXRoleAttribute) == kAXButtonRole {
                let names = ["AXIdentifier", kAXDescriptionAttribute, kAXTitleAttribute].compactMap { child.string($0) }
                buttons.append((child, TabButtonInfo(subrole: child.string(kAXSubroleAttribute), names: names)))
            }
            level = level.flatMap { $0.elements(kAXChildrenAttribute) }
        }
        return TabCloseButton.pick(buttons.map(\.info)).map { buttons[$0].element }
    }

    /// True once the browser has taken the tab away: its element is no longer valid.
    static func isGone(_ tab: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(tab, kAXRoleAttribute as CFString, &value) == .invalidUIElement
    }

    /// A tab is a radio button: its value is 1 when it is the selected tab.
    static func isSelected(_ tab: AXUIElement) -> Bool {
        (tab.copyAttribute(kAXValueAttribute) as? NSNumber)?.boolValue ?? false
    }

    /// Presses the tab's × if it shows one. Returns whether it pressed.
    static func pressCloseButton(_ tab: AXUIElement) -> Bool {
        closeButton(of: tab)?.perform(kAXPressAction) == true
    }

    /// Selects the tab in its window; the browser stays behind.
    static func select(_ tab: AXUIElement) -> Bool {
        isSelected(tab) || tab.perform(kAXPressAction)
    }

    enum SecondTry: String, Sendable {
        case closeButton, menuItem, notSelected, noMenuItem, menuItemDisabled
    }

    /// With the tab selected: its × if it shows one now, else the app's ⌘W menu
    /// item, after making the tab's window the app's main window so the menu
    /// acts on it. Never presses ⌘W unless this very tab is the selected one.
    static func closeSelected(_ tab: AXUIElement, window: AXUIElement?, pid: pid_t) -> SecondTry {
        if pressCloseButton(tab) { return .closeButton }
        guard isSelected(tab) else { return .notSelected }
        guard let item = closeTabMenuItem(of: AXUIElementCreateApplication(pid)) else { return .noMenuItem }
        guard item.bool(kAXEnabledAttribute) != false else { return .menuItemDisabled }
        window?.set(kAXMainAttribute, kCFBooleanTrue)
        return item.perform(kAXPressAction) ? .menuItem : .menuItemDisabled
    }

    /// The ⌘W item in the app's first few menus (File, or Shell in Terminal).
    private static func closeTabMenuItem(of app: AXUIElement) -> AXUIElement? {
        guard let bar = app.element(kAXMenuBarAttribute) else { return nil }
        for top in bar.elements(kAXChildrenAttribute).prefix(5) {
            for menu in top.elements(kAXChildrenAttribute) {
                for item in menu.elements(kAXChildrenAttribute) {
                    let modifiers = (item.copyAttribute(kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue
                    if CloseTabShortcut.matches(cmdChar: item.string(kAXMenuItemCmdCharAttribute), modifiers: modifiers) {
                        return item
                    }
                }
            }
        }
        return nil
    }
}

/// Runs a tab close on the browser's own queue, so a busy browser never holds up
/// the list, then has the window's tabs read again. One-shot waits only.
@MainActor
enum TabCloser {
    /// The browser needs a moment to take a closed tab out of its tab bar
    /// (Chrome animates it), and to show a selected tab's ×.
    private static let settle: Duration = .milliseconds(400)

    /// `refresh` redraws the list once the window's tabs were read again.
    static func close(_ tab: BrowserTab, window: AXUIElement?, queues: AppQueues, refresh: @escaping @MainActor @Sendable () -> Void) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(tab.element, &pid) == .success else { return }
        let appPID = pid
        let windowID = tab.windowID
        let target = SendableElement(element: tab.element)
        let windowElement = window.map { SendableElement(element: $0) }
        let previous = TabStore.shared.tabs(of: windowID)?
            .first { $0.isSelected && $0.id != tab.id }
            .map { SendableElement(element: $0.element) }
        // Gone from the list at once; the read after the close confirms it, or
        // brings the tab back if the browser kept it.
        TabStore.shared.remove(tab)
        refresh()

        Task { @MainActor in
            let shape = await ask(queues, appPID) { TabClose.describe(target.element) }
            Log.registry.notice("Tab close in window \(windowID, privacy: .public), tab shows \(shape, privacy: .public)")

            if await ask(queues, appPID, { TabClose.pressCloseButton(target.element) }) {
                try? await Task.sleep(for: settle)
                if await ask(queues, appPID, { TabClose.isGone(target.element) }) { return finish(windowID, refresh, "closed by its ×") }
            }
            guard await ask(queues, appPID, { TabClose.select(target.element) }) else { return finish(windowID, refresh, "could not select the tab") }
            try? await Task.sleep(for: settle)
            if await ask(queues, appPID, { TabClose.isGone(target.element) }) { return finish(windowID, refresh, "closed") }

            let second = await ask(queues, appPID) { TabClose.closeSelected(target.element, window: windowElement?.element, pid: appPID) }
            try? await Task.sleep(for: settle)
            if await ask(queues, appPID, { TabClose.isGone(target.element) }) { return finish(windowID, refresh, "closed by \(second.rawValue)") }
            // Not closed (a pinned tab, or a browser that refused): leave the
            // window showing the tab it showed before.
            if let previous { _ = await ask(queues, appPID) { previous.element.perform(kAXPressAction) } }
            finish(windowID, refresh, "not closed, tried \(second.rawValue)")
        }
    }

    /// Runs `work` on the app's queue and waits for its answer.
    private static func ask<T: Sendable>(_ queues: AppQueues, _ pid: pid_t, _ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            // The body runs at once, on the caller's actor: the main actor.
            MainActor.assumeIsolated {
                queues.run(for: pid, work, then: { continuation.resume(returning: $0) })
            }
        }
    }

    private static func finish(_ windowID: CGWindowID, _ refresh: @MainActor @Sendable () -> Void, _ step: String) {
        Log.registry.notice("Tab close in window \(windowID, privacy: .public): \(step, privacy: .public)")
        TabStore.shared.forget(windowID)
        refresh()
    }
}
