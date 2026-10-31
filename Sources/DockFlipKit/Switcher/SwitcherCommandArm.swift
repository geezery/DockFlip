import Foundation

/// Whether letting go of ⌘ may switch: the switcher's ⌘ arm. Pure, unit-tested.
///
/// The key events can't be trusted as ⌘'s state: every modifier change
/// without ⌘ (⇧ for ⇧Tab, ⌃, ⌥) also arrives as a release, and the panel's
/// monitor and the flags tap both send each change, so copies come in late.
/// So only the live ⌘ state arms, and one release disarms.
public struct SwitcherCommandArm: Equatable {
    /// The next ⌘ release switches.
    public private(set) var isArmed = false

    public init() {}

    /// The switcher opens: armed only while ⌘ is still held (a quick ⌘Tab
    /// that let go already switched as it opened).
    public mutating func open(commandHeld: Bool) {
        isArmed = commandHeld
    }

    /// ⌘ was pressed while the switcher is open, say after letting go of it
    /// to filter. A late copy can arrive with ⌘ already up: it does not re-arm.
    public mutating func pressed(commandHeld: Bool) {
        if commandHeld { isArmed = true }
    }

    /// ⌘ was released. True when this release switches; only the first one
    /// after arming does, later ones (other modifiers, copies) do nothing.
    public mutating func released() -> Bool {
        defer { isArmed = false }
        return isArmed
    }

    /// The switcher closed.
    public mutating func reset() {
        isArmed = false
    }
}
