import Testing
@testable import DockFlipKit

@Suite("SwitcherFilter")
struct SwitcherFilterTests {
    @Test func matchesEveryWordAnywhere() {
        #expect(SwitcherFilter.matches("team", fields: ["Chat | HVV", "Microsoft Teams"]))
        #expect(SwitcherFilter.matches("TEAMS chat", fields: ["Chat | HVV", "Microsoft Teams"]))
        #expect(!SwitcherFilter.matches("team excel", fields: ["Chat | HVV", "Microsoft Teams"]))
    }

    @Test func accentsAreLetters() {
        #expect(!SwitcherFilter.matches("öö", fields: ["Inbox", "Microsoft Outlook"]))
        #expect(!SwitcherFilter.matches("paate", fields: ["dockflip — zsh", "Pääte"]))
        #expect(SwitcherFilter.matches("PÄÄ", fields: ["dockflip — zsh", "Pääte"]))
        // Decomposed "ä" (a + combining diaeresis), as in many file names.
        #expect(SwitcherFilter.matches("pää", fields: ["Pa\u{308}a\u{308}te"]))
    }

    @Test func emptyQueryMatchesAll() {
        #expect(SwitcherFilter.matches("   ", fields: ["anything"]))
    }
}
