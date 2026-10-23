import AppKit
import CoreGraphics

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
final class SwitcherKeyTaps {
    var onCommandReleased: (() -> Void)?
    /// Returns true when the input was consumed.
    var onSwitcherKey: ((SwitcherInput) -> Bool)?

    private var flagsTap: CFMachPort?
    private var keysTap: CFMachPort?
    /// The switcher is open and wants its keys. The key tap is on only while this
    /// is true; anything else would swallow ⌥ and ⌃ characters (@, {, [ …) everywhere.
    private var keysWanted = false
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
        keysWanted = enabled
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
            // macOS switched the tap off (it was slow): back on only while switching.
            // This notice can arrive after the switcher has closed; turning the tap
            // on then would leave it on for good.
            if keysWanted, let keysTap { CGEvent.tapEnable(tap: keysTap, enable: true) }
            return false
        case .keyDown where !keysWanted:
            // The tap is on although the switcher is closed: switch it off and
            // let typing through untouched.
            if let keysTap { CGEvent.tapEnable(tap: keysTap, enable: false) }
            return false
        case .keyDown:
            let keyCode = UInt32(truncatingIfNeeded: code)
            let command = event.flags.contains(.maskCommand)
            // ⌘Tab belongs to the hot key; let it through.
            if keyCode == KeyCode.tab && command { return false }
            let input = SwitcherInput.from(
                keyCode: keyCode, command: command, shift: event.flags.contains(.maskShift),
                text: SwitcherText.typed(NSEvent(cgEvent: event))
            )
            // Keys that mean nothing to the switcher are swallowed too: nothing
            // reaches the app underneath while the switcher is open.
            if input == nil || onSwitcherKey?(input!) == true {
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

extension SwitcherInput {
    /// What a key press means to the open switcher, or nil for keys that mean
    /// nothing. Shared by the key tap and the panel's own key events, so both
    /// paths (normal, and secure keyboard input) behave the same.
    static func from(keyCode: UInt32, command: Bool, shift: Bool, text: @autoclosure () -> String?) -> SwitcherInput? {
        switch keyCode {
        case KeyCode.tab: return command ? nil : .commandTab(shift: shift) // plain Tab steps while filtering
        case KeyCode.escape: return .escape
        case KeyCode.left: return .left
        case KeyCode.right: return .right
        case KeyCode.returnKey, KeyCode.keypadEnter: return .enter
        case KeyCode.delete: return .deleteBackward
        default: return text().map { .text($0) }
        }
    }
}

/// The text a key press types, ignoring ⌘ (held while switching), or nil for
/// keys that type nothing (function keys, ⌃ and ⌥ combinations).
enum SwitcherText {
    static func typed(_ event: NSEvent?) -> String? {
        guard let event, event.type == .keyDown,
              !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option),
              let text = event.charactersIgnoringModifiers, !text.isEmpty,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .privateUse })
        else { return nil }
        return text
    }
}

private func flagsTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon {
        let tap = Unmanaged<SwitcherKeyTaps>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated {
            Perf.shared.measure("keys.flags", quiet: true) { tap.flagsChanged(type: type, event: event) }
        }
    }
    return Unmanaged.passUnretained(event)
}

private func keysTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<SwitcherKeyTaps>.fromOpaque(refcon).takeUnretainedValue()
    let swallow: Bool = MainActor.assumeIsolated {
        tap.switcherKey(type: type, event: event)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
