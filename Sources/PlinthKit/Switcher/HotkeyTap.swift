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

/// Keyboard event tap. Translates raw key events into `HotkeyCommand`s and
/// swallows only the keys Plinth actually used.
@MainActor
final class HotkeyTap {
    /// Returns true when the command was handled (the key is then swallowed).
    var handler: ((HotkeyCommand) -> Bool)?
    var isSwitcherActive: (() -> Bool)?
    var isEnabled: (() -> Bool)?

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    /// Key codes whose keyDown we swallowed; their keyUp is swallowed too.
    private var swallowed = Set<Int64>()

    private enum Key {
        static let tab: Int64 = 48
        static let escape: Int64 = 53
        static let left: Int64 = 123
        static let right: Int64 = 124
        static let down: Int64 = 125
        static let up: Int64 = 126
        static let returnKey: Int64 = 36
        static let keypadEnter: Int64 = 76
        static let d: Int64 = 2
        static let e: Int64 = 14
        /// ANSI key codes for 1…9.
        static let digits: [Int64] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
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
            let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
            Log.keys.error("Event tap was disabled by macOS (\(reason, privacy: .public)); re-enabling")
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false

        case .keyDown:
            guard isEnabled?() ?? true else { return false }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let command = flags.contains(.maskCommand)
            let option = flags.contains(.maskAlternate)
            let control = flags.contains(.maskControl)
            let shift = flags.contains(.maskShift)

            // ⌘Tab / ⌘⇧Tab
            if code == Key.tab, command, !option, !control {
                return run(.switcher(.commandTab(shift: shift)), code: code)
            }

            // Keys while the switcher is open.
            if isSwitcherActive?() == true {
                switch code {
                case Key.escape: return run(.switcher(.escape), code: code)
                case Key.left: return run(.switcher(.left), code: code)
                case Key.right: return run(.switcher(.right), code: code)
                case Key.returnKey, Key.keypadEnter: return run(.switcher(.enter), code: code)
                default:
                    swallowed.insert(code)
                    return true
                }
            }

            // ⌃⌥ — the Win key.
            guard control, option, !command else { return false }
            switch code {
            case Key.left: return run(shift ? .moveToDisplay(.left) : .snap(.left), code: code)
            case Key.right: return run(shift ? .moveToDisplay(.right) : .snap(.right), code: code)
            case Key.up where !shift: return run(.snap(.up), code: code)
            case Key.down where !shift: return run(.snap(.down), code: code)
            case Key.d where !shift: return run(.showDesktop, code: code)
            case Key.e where !shift: return run(.newFinderWindow, code: code)
            default:
                if !shift, let index = Key.digits.firstIndex(of: code) {
                    return run(.taskbarItem(index), code: code)
                }
                return false
            }

        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            return swallowed.remove(code) != nil

        case .flagsChanged:
            if !event.flags.contains(.maskCommand), isSwitcherActive?() == true {
                _ = handler?(.switcher(.commandReleased))
            }
            return false

        default:
            return false
        }
    }

    private func run(_ command: HotkeyCommand, code: Int64) -> Bool {
        guard handler?(command) == true else { return false }
        swallowed.insert(code)
        return true
    }
}

/// C callback for the event tap. Runs on the main run loop.
private func hotkeyTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
    let swallow: Bool = MainActor.assumeIsolated {
        // macOS turns the tap off if this takes too long, so it is always measured.
        Perf.shared.measure("keys.tap", quiet: true) {
            tap.shouldSwallow(type: type, event: event)
        }
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
