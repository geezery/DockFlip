import AppKit
import Carbon.HIToolbox
import CoreGraphics

public enum SwitcherInput: Equatable {
    case commandTab(shift: Bool)
    case escape
    case left
    case right
    case enter
    case commandReleased
}

public enum SnapKey: Equatable {
    case left, right, up, down
}

/// Everything Plinth does from the keyboard. ⌃⌥ plays the role of the Win key.
public enum HotkeyCommand: Equatable {
    case switcher(SwitcherInput)
    case snap(SnapKey)
    case moveToDisplay(SnapKey)   // ⌃⌥⇧← / →
    case taskbarItem(Int)         // ⌃⌥1…9, zero-based
    case showDesktop              // ⌃⌥D
    case newFinderWindow          // ⌃⌥E
}

private enum KeyCode {
    static let tab: UInt32 = 48
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

    private var refs: [EventHotKeyRef] = []
    private var commands: [UInt32: HotkeyCommand] = [:]
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x504C_4E54 // "PLNT"

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
            list.append((digit, win, .taskbarItem(index)))
        }
        return list.map { (key: $0.0, modifiers: $0.1, command: $0.2) }
    }

    var registeredCount: Int { refs.count }

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
                refs.append(ref)
                commands[id] = binding.command
            } else {
                Log.keys.error("RegisterEventHotKey failed for key \(binding.key, privacy: .public) (status \(status, privacy: .public))")
            }
        }
        Log.keys.notice("Registered \(self.refs.count, privacy: .public) global shortcuts")
    }

    func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs = []
        commands = [:]
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

/// The two event taps the ⌘Tab switcher needs on top of the hot keys:
/// - a listen-only tap for modifier changes, to notice ⌘ being released (secure
///   input does not hide modifier changes);
/// - a key tap that is switched on only while the switcher is open, for Esc,
///   the arrow keys and Return. The rest of the time no tap touches typing.
///   It sits at the HID level, the earliest point: on macOS 26 the Game Overlay
///   grabs ⌘Esc further down the line, and ⌘ is held while switching (AltTab #5585).
///   Secure input hides key presses from every tap; then the switcher panel,
///   which is the key window, gets them as ordinary key events.
@MainActor
final class HotkeyTap {
    var onCommandReleased: (() -> Void)?
    /// Returns true when the input was consumed.
    var onSwitcherKey: ((SwitcherInput) -> Bool)?

    private var flagsTap: CFMachPort?
    private var keysTap: CFMachPort?
    /// Key codes whose keyDown we swallowed; their keyUp is swallowed too.
    private var swallowed = Set<Int64>()

    func start() -> Bool {
        guard flagsTap == nil else { return true }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let flags = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << CGEventMask(CGEventType.flagsChanged.rawValue),
            callback: flagsTapCallback,
            userInfo: userInfo
        ) else { return false }

        let keyMask = (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue))
            | (CGEventMask(1) << CGEventMask(CGEventType.keyUp.rawValue))
        guard let keys = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyMask,
            callback: keysTapCallback,
            userInfo: userInfo
        ) else { return false }

        for port in [flags, keys] {
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0), .commonModes)
        }
        CGEvent.tapEnable(tap: flags, enable: true)
        CGEvent.tapEnable(tap: keys, enable: false)
        flagsTap = flags
        keysTap = keys
        return true
    }

    /// The key tap is on only while the switcher is open.
    func setSwitcherKeysEnabled(_ enabled: Bool) {
        guard let keysTap else { return }
        if CGEvent.tapIsEnabled(tap: keysTap) != enabled {
            CGEvent.tapEnable(tap: keysTap, enable: enabled)
        }
        if !enabled { swallowed.removeAll() }
    }

    fileprivate func flagsChanged(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Log.keys.error("Modifier tap was disabled by macOS; re-enabling")
            if let flagsTap { CGEvent.tapEnable(tap: flagsTap, enable: true) }
        case .flagsChanged:
            if !event.flags.contains(.maskCommand) { onCommandReleased?() }
        default:
            break
        }
    }

    /// Returns true when the event must be swallowed.
    fileprivate func switcherKey(type: CGEventType, event: CGEvent) -> Bool {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return false
        case .keyDown:
            let input: SwitcherInput
            switch UInt32(truncatingIfNeeded: code) {
            case KeyCode.tab: return false // the hot key handles Tab
            case KeyCode.escape: input = .escape
            case KeyCode.left: input = .left
            case KeyCode.right: input = .right
            case KeyCode.returnKey, KeyCode.keypadEnter: input = .enter
            default:
                // Other keys do nothing while the switcher is open.
                swallowed.insert(code)
                return true
            }
            if onSwitcherKey?(input) == true {
                swallowed.insert(code)
                return true
            }
            return false
        case .keyUp:
            return swallowed.remove(code) != nil
        default:
            return false
        }
    }
}

private func flagsTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon {
        let tap = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated {
            Perf.shared.measure("keys.flags", quiet: true) { tap.flagsChanged(type: type, event: event) }
        }
    }
    return Unmanaged.passUnretained(event)
}

private func keysTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
    let swallow: Bool = MainActor.assumeIsolated {
        tap.switcherKey(type: type, event: event)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
