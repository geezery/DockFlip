import Testing
@testable import DockFlipKit

/// Which button inside a tab is its ×. Pressing the wrong one would mute a tab
/// instead of closing it, so a tab with two unnamed buttons gets no press at all.
@Suite("TabCloseButton")
struct TabCloseButtonTests {
    func button(_ subrole: String? = nil, _ names: String...) -> TabButtonInfo {
        TabButtonInfo(subrole: subrole, names: names)
    }

    @Test func closeSubroleWins() {
        // Finder and Terminal mark their × with a subrole.
        #expect(TabCloseButton.pick([button(nil, "Mute"), button("AXCloseButton", "Sulje")]) == 1)
    }

    @Test func englishNameFindsIt() {
        #expect(TabCloseButton.pick([button(nil, "Mute tab"), button(nil, "Close Tab")]) == 1)
        #expect(TabCloseButton.pick([button(nil, "tab-close-button", "")]) == 0)
    }

    @Test func aTabsOnlyButtonIsItsCloseButton() {
        // A Finnish browser names its × "Sulje välilehti": no "close" to find.
        #expect(TabCloseButton.pick([button(nil, "Sulje välilehti")]) == 0)
    }

    @Test func twoUnnamedButtonsAreLeftAlone() {
        #expect(TabCloseButton.pick([button(nil, "Mykistä"), button(nil, "Sulje")]) == nil)
        #expect(TabCloseButton.pick([]) == nil)
    }
}

/// The menu fallback presses ⌘W, and only ⌘W: ⇧⌘W closes the whole window.
@Suite("CloseTabShortcut")
struct CloseTabShortcutTests {
    @Test func commandWAlone() {
        #expect(CloseTabShortcut.matches(cmdChar: "W", modifiers: 0))
        #expect(CloseTabShortcut.matches(cmdChar: "w", modifiers: 0))
    }

    @Test func notOtherShortcuts() {
        #expect(!CloseTabShortcut.matches(cmdChar: "W", modifiers: 1)) // ⇧⌘W: Close Window
        #expect(!CloseTabShortcut.matches(cmdChar: "W", modifiers: 2)) // ⌥⌘W: Close All
        #expect(!CloseTabShortcut.matches(cmdChar: "Q", modifiers: 0))
        #expect(!CloseTabShortcut.matches(cmdChar: nil, modifiers: nil))
    }
}
