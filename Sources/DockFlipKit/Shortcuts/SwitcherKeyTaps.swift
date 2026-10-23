import AppKit
import CoreGraphics

/// The two event taps the ⌘Tab switcher needs on top of the hot keys:
/// - a listen-only tap for modifier changes, to notice ⌘ being released (secure
///   input does not hide modifier changes);
/// - a key tap that is switched on only while the switcher is open, for Esc alone.
///   It sits at the HID level, the earliest point: on macOS 26 the Game Overlay
///   grabs ⌘Esc further down the line, and ⌘ is held while switching (AltTab #5585).
///   Every other key reaches the switcher panel, which is the key window, as an
///   ordinary key event — as AltTab does. The rest of the time no tap touches typing.
@MainActor
final class SwitcherKeyTaps {
    var onCommandReleased: (() -> Void)?
    /// Returns true when Esc was consumed.
    var onEscape: (() -> Bool)?

    private var flagsTap: CFMachPort?
    private var keysTap: CFMachPort?
    /// The switcher is open and wants Esc. The key tap is on only while this is
    /// true; anything else would leave a tap in front of all typing.
    private var keysWanted = false
    /// We swallowed Esc's keyDown; its keyUp is swallowed too.
    private var escapeSwallowed = false

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
        if !enabled { escapeSwallowed = false }
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

    /// Returns true when the event must be swallowed. Only Esc ever is.
    fileprivate func switcherKey(type: CGEventType, event: CGEvent) -> Bool {
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
            guard Self.isEscape(event) else { return false }
            escapeSwallowed = onEscape?() == true
            return escapeSwallowed
        case .keyUp:
            guard escapeSwallowed, Self.isEscape(event) else { return false }
            escapeSwallowed = false
            return true
        default:
            return false
        }
    }

    private static func isEscape(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventKeycode) == Int64(KeyCode.escape)
    }
}

extension SwitcherInput {
    /// What a key press the switcher panel receives means to the open switcher,
    /// or nil for keys that mean nothing.
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
