import AppKit
import Testing
@testable import DockFlipKit

/// The switcher's key mapping broke twice in October 2026 (06566db: ⌥ characters
/// swallowed; ccec8a2: Esc). These pin what each key means to the open switcher.
@Suite("SwitcherInput.from")
struct SwitcherInputFromTests {
    private func map(_ keyCode: UInt32, command: Bool = false, shift: Bool = false, text: String? = nil) -> SwitcherInput? {
        SwitcherInput.from(keyCode: keyCode, command: command, shift: shift, text: text)
    }

    @Test func plainTabSteps() {
        let forward = map(KeyCode.tab)
        let back = map(KeyCode.tab, shift: true)
        #expect(forward == .commandTab(shift: false))
        #expect(back == .commandTab(shift: true))
    }

    @Test func tabWithCommandIsLeftToTheHotKey() {
        // ⌘Tab itself comes from the hot key; mapping it here too would step twice.
        let plain = map(KeyCode.tab, command: true)
        let shifted = map(KeyCode.tab, command: true, shift: true)
        #expect(plain == nil)
        #expect(shifted == nil)
    }

    @Test func arrowsStepAndAreNeverText() {
        // Arrow keys carry private-use characters; they must not fall through to text.
        let left = map(KeyCode.left, text: "\u{F702}")
        let up = map(KeyCode.up, text: "\u{F700}")
        let right = map(KeyCode.right, text: "\u{F703}")
        let down = map(KeyCode.down, text: "\u{F701}")
        #expect(left == .previous)
        #expect(up == .previous)
        #expect(right == .next)
        #expect(down == .next)
    }

    @Test func returnAndKeypadEnterCommit() {
        let returnKey = map(KeyCode.returnKey, text: "\r")
        let enter = map(KeyCode.keypadEnter, text: "\u{3}")
        #expect(returnKey == .enter)
        #expect(enter == .enter)
    }

    @Test func escapeAndDelete() {
        let escape = map(KeyCode.escape, text: "\u{1B}")
        let delete = map(KeyCode.delete, text: "\u{7F}")
        #expect(escape == .escape)
        #expect(delete == .deleteBackward)
    }

    @Test func otherKeysTypeTheirText() {
        let letter = map(0, text: "a")
        let withCommand = map(0, command: true, text: "a")
        #expect(letter == .text("a"))
        #expect(withCommand == .text("a"))
    }

    @Test func keysThatTypeNothingMeanNothing() {
        let none = map(122, text: nil) // F1
        #expect(none == nil)
    }

    @Test func textIsReadOnlyForOtherKeys() {
        // The text closure can be costly (it reads the event); the named keys skip it.
        var reads = 0
        func read() -> String? { reads += 1; return "x" }
        let tab = SwitcherInput.from(keyCode: KeyCode.tab, command: false, shift: false, text: read())
        #expect(tab == .commandTab(shift: false))
        #expect(reads == 0)
    }

    @Test func flagsMapOnCommandOnly() {
        #expect(SwitcherInput.fromFlags(command: true) == .commandPressed)
        #expect(SwitcherInput.fromFlags(command: false) == .commandReleased)
    }
}

@Suite("SwitcherText.typed")
struct SwitcherTextTypedTests {
    private func key(_ characters: String, flags: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown, keyCode: UInt16 = 0) -> NSEvent? {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: keyCode)
    }

    @Test func plainAndShiftedLettersType() {
        let plain = key("a")
        let shifted = key("A", flags: .shift)
        #expect(plain != nil)
        #expect(SwitcherText.typed(plain) == "a")
        #expect(SwitcherText.typed(shifted) == "A")
    }

    @Test func commandIsIgnored() {
        // ⌘ is held while switching, so ⌘A still filters by "a".
        let event = key("a", flags: .command)
        #expect(SwitcherText.typed(event) == "a")
    }

    @Test func optionAndControlTypeNothing() {
        // ⌥2 types @ on Finnish keyboards: the switcher must not claim it as its text.
        let option = key("2", flags: .option)
        let control = key("a", flags: .control)
        #expect(option != nil)
        #expect(SwitcherText.typed(option) == nil)
        #expect(SwitcherText.typed(control) == nil)
    }

    @Test func controlAndFunctionCharactersTypeNothing() {
        let escape = key("\u{1B}", keyCode: UInt16(KeyCode.escape))
        let up = key("\u{F700}", keyCode: UInt16(KeyCode.up))
        let returnKey = key("\r", keyCode: UInt16(KeyCode.returnKey))
        #expect(escape != nil)
        #expect(SwitcherText.typed(escape) == nil)
        #expect(SwitcherText.typed(up) == nil)
        #expect(SwitcherText.typed(returnKey) == nil)
    }

    @Test func keyUpAndNoEventTypeNothing() {
        let up = key("a", type: .keyUp)
        #expect(up != nil)
        #expect(SwitcherText.typed(up) == nil)
        #expect(SwitcherText.typed(nil) == nil)
    }
}
