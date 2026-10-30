/// Which of DockFlip's shortcuts macOS gave it, and whether that makes ⌘Tab DockFlip's.
///
/// A hot key fails to register when another app already holds it (AltTab holds
/// ⌘Tab). DockFlip turns macOS's own ⌘Tab off before it registers, so it must know
/// whether it got ⌘Tab: otherwise ⌘Tab does nothing at all.
struct HotKeyRegistration: Equatable {
    /// The two bindings that make up ⌘Tab.
    static let commandTab: [HotkeyCommand] = [
        .switcher(.commandTab(shift: false)),
        .switcher(.commandTab(shift: true))
    ]

    /// Commands whose shortcut DockFlip holds, in registration order.
    private(set) var registered: [HotkeyCommand] = []
    /// Commands whose shortcut failed to register.
    private(set) var failed: [HotkeyCommand] = []

    mutating func record(_ command: HotkeyCommand, registered ok: Bool) {
        if ok {
            registered.append(command)
        } else {
            failed.append(command)
        }
    }

    /// DockFlip owns ⌘Tab only with both ⌘Tab and ⌘⇧Tab. With one of them another app
    /// holds ⌘Tab, and half of DockFlip's switcher beside half of another is worse
    /// than macOS's own.
    var ownsCommandTab: Bool {
        Self.commandTab.allSatisfy { registered.contains($0) }
    }

    /// The ⌘Tab bindings DockFlip got but must let go of, because it does not own ⌘Tab.
    var commandTabToRelease: [HotkeyCommand] {
        ownsCommandTab ? [] : registered.filter { Self.commandTab.contains($0) }
    }

    mutating func release(_ command: HotkeyCommand) {
        registered.removeAll { $0 == command }
    }
}

extension HotkeyCommand {
    /// The shortcut as people type it, for the log ("⌘Tab", "⌃⌥←"). Never a title.
    var shortcutName: String {
        switch self {
        case .switcher(.commandTab(let shift)): return shift ? "⌘⇧Tab" : "⌘Tab"
        case .switcher: return "switcher key"
        case .snap(let key): return "⌃⌥" + key.arrow
        case .moveToDisplay(let key): return "⌃⌥⇧" + key.arrow
        case .dockItem(let index): return "⌃⌥\(index + 1)"
        case .showDesktop: return "⌃⌥D"
        case .newFinderWindow: return "⌃⌥E"
        }
    }
}

private extension SnapKey {
    var arrow: String {
        switch self {
        case .left: return "←"
        case .right: return "→"
        case .up: return "↑"
        case .down: return "↓"
        }
    }
}
