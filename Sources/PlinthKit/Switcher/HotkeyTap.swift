import AppKit
import CoreGraphics

public enum SwitcherInput: Equatable {
    case commandTab(shift: Bool)
    case escape
    case left
    case right
    case enter
    case commandReleased
}

/// Keyboard event tap for ⌘Tab. Translates raw key events into `SwitcherInput`
/// and swallows only the keys the switcher actually used.
@MainActor
final class HotkeyTap {
    /// Returns true when the input was consumed.
    var handler: ((SwitcherInput) -> Bool)?
    var isActive: (() -> Bool)?

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    /// Key codes whose keyDown we swallowed; their keyUp is swallowed too.
    private var swallowed = Set<Int64>()

    private enum Key {
        static let tab: Int64 = 48
        static let escape: Int64 = 53
        static let left: Int64 = 123
        static let right: Int64 = 124
        static let returnKey: Int64 = 36
        static let keypadEnter: Int64 = 76
    }

    func start() -> Bool {
        guard port == nil else { return true }
        let mask = (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue))
            | (CGEventMask(1) << CGEventMask(CGEventType.keyUp.rawValue))
            | (CGEventMask(1) << CGEventMask(CGEventType.flagsChanged.rawValue))
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    /// Returns true when the event must be swallowed.
    fileprivate func shouldSwallow(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false

        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            if code == Key.tab,
               flags.contains(.maskCommand),
               !flags.contains(.maskAlternate),
               !flags.contains(.maskControl) {
                return consume(.commandTab(shift: flags.contains(.maskShift)), code: code)
            }

            guard isActive?() == true else { return false }
            let input: SwitcherInput
            switch code {
            case Key.escape: input = .escape
            case Key.left: input = .left
            case Key.right: input = .right
            case Key.returnKey, Key.keypadEnter: input = .enter
            default:
                // Other keys do nothing while the switcher is open.
                swallowed.insert(code)
                return true
            }
            return consume(input, code: code)

        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            return swallowed.remove(code) != nil

        case .flagsChanged:
            if !event.flags.contains(.maskCommand) {
                _ = handler?(.commandReleased)
            }
            return false

        default:
            return false
        }
    }

    private func consume(_ input: SwitcherInput, code: Int64) -> Bool {
        guard handler?(input) == true else { return false }
        swallowed.insert(code)
        return true
    }
}

/// C callback for the event tap. Runs on the main run loop.
private func hotkeyTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
    let swallow: Bool = MainActor.assumeIsolated {
        tap.shouldSwallow(type: type, event: event)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
