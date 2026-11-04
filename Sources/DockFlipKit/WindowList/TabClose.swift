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

/// Closes a browser tab from the Dock list by pressing the tab's own × through
/// Accessibility, so the browser stays where it is and DockFlip stays inactive.
/// The browser may still ask first (a page with unsent text), as it would anyway.
enum TabClose {
    enum Outcome: String, Sendable {
        /// The × was pressed.
        case pressed
        /// The tab had no × (Chrome and Firefox hide it on narrow tabs) and was
        /// selected instead, which shows its ×; look again shortly.
        case selected
        /// Nothing to press (a pinned tab), or the browser did not answer.
        case noButton
    }

    /// The tab's close button, among its buttons up to two levels down.
    /// Thread-safe: call it on the app's queue.
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

    /// Presses the tab's ×, or selects the tab when it shows none.
    static func firstTry(_ tab: AXUIElement, isSelected: Bool) -> Outcome {
        if let button = closeButton(of: tab) {
            return button.perform(kAXPressAction) ? .pressed : .noButton
        }
        guard !isSelected, tab.perform(kAXPressAction) else { return .noButton }
        return .selected
    }

    /// After `.selected`: presses the × the tab now shows. With still no × (a
    /// pinned tab), selects the tab that was selected before, so the window is
    /// left as it was.
    static func secondTry(_ tab: AXUIElement, restoring previous: AXUIElement?) -> Outcome {
        if let button = closeButton(of: tab), button.perform(kAXPressAction) {
            return .pressed
        }
        previous?.perform(kAXPressAction)
        return .noButton
    }
}

/// Runs a tab close on the browser's own queue, so a busy browser never holds up
/// the list, then has the window's tabs read again. One-shot waits only.
@MainActor
enum TabCloser {
    /// The browser needs a moment to show a selected tab's × and to take a
    /// closed tab out of its tab bar.
    private static let settle: Duration = .milliseconds(250)

    /// `refresh` redraws the list once the window's tabs were read again.
    static func close(_ tab: BrowserTab, queues: AppQueues, refresh: @escaping @MainActor @Sendable () -> Void) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(tab.element, &pid) == .success else { return }
        let windowID = tab.windowID
        let target = SendableElement(element: tab.element)
        let previous = TabStore.shared.tabs(of: windowID)?
            .first { $0.isSelected && $0.id != tab.id }
            .map { SendableElement(element: $0.element) }
        let isSelected = tab.isSelected
        // Gone from the list at once; the read after the close confirms it, or
        // brings the tab back if the browser kept it.
        TabStore.shared.remove(tab)
        refresh()

        queues.run(for: pid, { TabClose.firstTry(target.element, isSelected: isSelected) }, then: { outcome in
            guard outcome == .selected else {
                finish(windowID, outcome, refresh: refresh)
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: settle)
                queues.run(for: pid, { TabClose.secondTry(target.element, restoring: previous?.element) }, then: { outcome in
                    finish(windowID, outcome, refresh: refresh)
                })
            }
        })
    }

    private static func finish(_ windowID: CGWindowID, _ outcome: TabClose.Outcome, refresh: @escaping @MainActor @Sendable () -> Void) {
        Log.registry.notice("Tab close in window \(windowID, privacy: .public): \(outcome.rawValue, privacy: .public)")
        Task { @MainActor in
            if outcome == .pressed { try? await Task.sleep(for: settle) }
            TabStore.shared.forget(windowID)
            refresh()
        }
    }
}
