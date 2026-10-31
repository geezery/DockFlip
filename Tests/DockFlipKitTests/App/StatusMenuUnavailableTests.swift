import AppKit
import Testing
@testable import DockFlipKit

/// A feature a new macOS broke shows as a status line in the menu bar menu, in
/// every language DockFlip offers.
@Suite("Menu: unavailable features")
@MainActor
struct StatusMenuUnavailableTests {
    /// The English text of each line, which is also its key.
    private let english: [UnavailableFeature: String] = [
        .commandTabSwitchOff: "Turning off macOS's own ⌘Tab: not available on this macOS version",
        .windowTracking: "Window tracking: not available on this macOS version",
        .otherSpaces: "Windows on other Spaces: not available on this macOS version",
        .dockLists: "Dock lists: not available on this macOS version"
    ]

    @Test func oneStatusLinePerFeature() throws {
        #expect(StatusMenu.unavailableItems([]).isEmpty)

        let features = UnavailableFeature.allCases
        let items = StatusMenu.unavailableItems(features)
        #expect(items.count == features.count)
        for (item, feature) in zip(items, features) {
            let key = try #require(english[feature])
            #expect(item.title == L(key))
            // A status line, like "⌘Tab: not active": there is nothing to click.
            #expect(item.isEnabled == false)
            #expect(item.action == nil)
        }
    }

    @Test(arguments: AppLanguage.all.map(\.code))
    func everyLineIsTranslated(_ code: String) throws {
        let strings = try LocalizableStringsTests.strings(code)
        for feature in UnavailableFeature.allCases {
            let key = try #require(english[feature])
            let value = try #require(strings[key], "\(code) lacks \"\(key)\"")
            #expect(!value.isEmpty)
            if code != "en" { #expect(value != key, "\(code) shows \"\(key)\" in English") }
        }
    }
}
