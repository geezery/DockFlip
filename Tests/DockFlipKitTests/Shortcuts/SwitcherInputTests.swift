import Testing
@testable import DockFlipKit

@Suite("SwitcherInput")
struct SwitcherInputTests {
    private func input(_ keyCode: UInt32, command: Bool = true, shift: Bool = false, text: String? = nil) -> SwitcherInput? {
        SwitcherInput.from(keyCode: keyCode, command: command, shift: shift, text: text)
    }

    @Test func arrowsMoveThroughTheStack() {
        #expect(input(KeyCode.right) == .right)
        #expect(input(KeyCode.left) == .left)
        // ↓ and ↑ step like → and ←, with or without ⌘ held.
        #expect(input(KeyCode.down) == .right)
        #expect(input(KeyCode.up) == .left)
        #expect(input(KeyCode.down, command: false) == .right)
        #expect(input(KeyCode.up, command: false) == .left)
    }

    @Test func otherKeys() {
        #expect(input(KeyCode.tab) == nil) // ⌘Tab itself comes from the hot key
        #expect(input(KeyCode.tab, command: false, shift: true) == .commandTab(shift: true))
        #expect(input(KeyCode.escape) == .escape)
        #expect(input(KeyCode.returnKey) == .enter)
        #expect(input(KeyCode.keypadEnter) == .enter)
        #expect(input(KeyCode.delete) == .deleteBackward)
        #expect(input(KeyCode.d, text: "d") == .text("d"))
        #expect(input(KeyCode.d) == nil)
    }
}
