import Testing
@testable import DockFlipKit

@Suite("SwitcherInput")
struct SwitcherInputTests {
    private func input(_ keyCode: UInt32, command: Bool = true, shift: Bool = false, text: String? = nil) -> SwitcherInput? {
        SwitcherInput.from(keyCode: keyCode, command: command, shift: shift, text: text)
    }

    @Test func arrowsMoveThroughTheStack() {
        #expect(input(KeyCode.right) == .next)
        #expect(input(KeyCode.left) == .previous)
        // ↓ and ↑ step like → and ←, with or without ⌘ held.
        #expect(input(KeyCode.down) == .next)
        #expect(input(KeyCode.up) == .previous)
        #expect(input(KeyCode.down, command: false) == .next)
        #expect(input(KeyCode.up, command: false) == .previous)
    }

    @Test func modifierChangeMapsOnCommandAlone() {
        let down = SwitcherInput.fromFlags(command: true)
        let up = SwitcherInput.fromFlags(command: false)
        #expect(down == .commandPressed)
        #expect(up == .commandReleased)
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
