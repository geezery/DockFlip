import AppKit
import Carbon.HIToolbox

// DockFlip's keyboard shortcuts: what they are (`HotkeyCommand`) and how they are
// caught (`GlobalHotKeys`). ⌃⌥ plays the Windows key: Win+D is ⌃⌥D, Win+← is ⌃⌥←.

public enum SwitcherInput: Equatable {
    case commandTab(shift: Bool)
    case escape
    /// Step back one window (← or ↑).
    case previous
    /// Step on one window (→ or ↓).
    case next
    case enter
    /// A modifier change with ⌘ up: ⌘ let go, or ⇧, ⌃ or ⌥ pressed or let go without it.
    case commandReleased
    /// A modifier change with ⌘ down: ⌘ pressed, or another modifier changed while it is held.
    case commandPressed
    /// Typed text: filters the switcher's windows.
    case text(String)
    case deleteBackward
}

public enum SnapKey: Equatable {
    case left, right, up, down
}

/// Everything DockFlip does from the keyboard. ⌃⌥ plays the role of the Win key.
public enum HotkeyCommand: Equatable {
    case switcher(SwitcherInput)
    case snap(SnapKey)
    case moveToDisplay(SnapKey)   // ⌃⌥⇧← / →
    case dockItem(Int)            // ⌃⌥1…9, zero-based
    case showDesktop              // ⌃⌥D
    case newFinderWindow          // ⌃⌥E
}

/// Virtual key codes (ANSI layout) DockFlip listens for.
enum KeyCode {
    static let tab: UInt32 = 48
    static let delete: UInt32 = 51
    static let escape: UInt32 = 53
    static let left: UInt32 = 123
    static let right: UInt32 = 124
    static let down: UInt32 = 125
    static let up: UInt32 = 126
    static let returnKey: UInt32 = 36
    static let keypadEnter: UInt32 = 76
    static let d: UInt32 = 2
    static let e: UInt32 = 14
    /// ANSI key codes for 1…9.
    static let digits: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
}

/// Global shortcuts registered with Carbon's `RegisterEventHotKey` (the approach
/// AltTab uses). macOS delivers these even while another app holds secure keyboard
/// input — Terminal's Secure Keyboard Entry, password fields — when event taps see
/// nothing. Registering them also means no tap sits in the path of normal typing.
@MainActor
final class GlobalHotKeys {
    var handler: ((HotkeyCommand) -> Void)?

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var commands: [UInt32: HotkeyCommand] = [:]
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x444B_464C // "DKFL"

    private static var bindings: [(key: UInt32, modifiers: UInt32, command: HotkeyCommand)] {
        let cmd = UInt32(cmdKey), shift = UInt32(shiftKey)
        let win = UInt32(controlKey) | UInt32(optionKey)
        var list: [(UInt32, UInt32, HotkeyCommand)] = [
            (KeyCode.tab, cmd, .switcher(.commandTab(shift: false))),
            (KeyCode.tab, cmd | shift, .switcher(.commandTab(shift: true))),
            (KeyCode.left, win, .snap(.left)),
            (KeyCode.right, win, .snap(.right)),
            (KeyCode.up, win, .snap(.up)),
            (KeyCode.down, win, .snap(.down)),
            (KeyCode.left, win | shift, .moveToDisplay(.left)),
            (KeyCode.right, win | shift, .moveToDisplay(.right)),
            (KeyCode.d, win, .showDesktop),
            (KeyCode.e, win, .newFinderWindow)
        ]
        for (index, digit) in KeyCode.digits.enumerated() {
            list.append((digit, win, .dockItem(index)))
        }
        return list.map { (key: $0.0, modifiers: $0.1, command: $0.2) }
    }

    var registeredCount: Int { refs.count }

    /// Which shortcuts the last `registerAll` got.
    private(set) var registration = HotKeyRegistration()

    /// True when ⌘Tab and ⌘⇧Tab are DockFlip's; false when another app holds ⌘Tab.
    var ownsCommandTab: Bool { registration.ownsCommandTab }

    func registerAll() {
        unregisterAll()
        installHandlerIfNeeded()
        for (index, binding) in Self.bindings.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                binding.key, binding.modifiers,
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref {
                refs[id] = ref
                commands[id] = binding.command
                registration.record(binding.command, registered: true)
            } else {
                // Usually another app holds it (eventHotKeyExistsErr, -9878).
                Log.keys.error("RegisterEventHotKey failed for \(binding.command.shortcutName, privacy: .public) (status \(status, privacy: .public))")
                registration.record(binding.command, registered: false)
            }
        }
        // Half of ⌘Tab is not kept: macOS gets the whole of it back (see Services).
        for command in registration.commandTabToRelease {
            for (id, held) in commands where held == command {
                if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
                commands[id] = nil
            }
            registration.release(command)
            Log.keys.notice("Let go of \(command.shortcutName, privacy: .public): another app holds ⌘Tab")
        }
        Log.keys.notice("Registered \(self.refs.count, privacy: .public) global shortcuts")
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs = [:]
        commands = [:]
        registration = HotKeyRegistration()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, me, &handlerRef)
        if status != noErr {
            Log.keys.error("InstallEventHandler failed (status \(status, privacy: .public))")
        }
    }

    fileprivate func fire(_ id: UInt32) {
        guard let command = commands[id] else { return }
        Perf.shared.measure("keys.hotkey") { handler?(command) }
    }
}

/// Carbon callback; runs on the main thread.
private func hotKeyEventHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr else { return status }
    let hotKeys = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
    let id = hotKeyID.id
    MainActor.assumeIsolated { hotKeys.fire(id) }
    return noErr
}
