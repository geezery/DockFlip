import Foundation
import Testing
@testable import DockFlipKit

/// Every language DockFlip offers has the same strings as English, so no step
/// of the app falls back to English in the middle of another language.
/// The files are read from `Resources/` in the source tree, as `make app` copies them.
@Suite("Localizable.strings")
struct LocalizableStringsTests {
    static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // App
        .deletingLastPathComponent() // DockFlipKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("Resources")

    static func strings(_ code: String) throws -> [String: String] {
        let url = resources.appendingPathComponent("\(code).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        // The same parser macOS uses for .strings files; a stray quote or missing ";" fails here.
        let list = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(list as? [String: String], "\(code) is not a strings file")
    }

    @Test(arguments: AppLanguage.all.map(\.code))
    func hasTheSameKeysAsEnglish(_ code: String) throws {
        let english = try Set(Self.strings("en").keys)
        let keys = try Set(Self.strings(code).keys)
        #expect(english.subtracting(keys).sorted() == [], "missing in \(code)")
        #expect(keys.subtracting(english).sorted() == [], "only in \(code)")
    }

    static let sources = resources.deletingLastPathComponent().appendingPathComponent("Sources")

    /// Every key the code uses has an English entry. Without one, `L("…")` and `Text("…")`
    /// show the English key in every language with no warning, and `hasTheSameKeysAsEnglish`
    /// cannot see it: all 15 files agree that the key is not there.
    @Test func everyKeyInSourcesIsInEnglish() throws {
        let used = try SourceStringKeys.scan(Self.sources)
        let english = try Set(Self.strings("en").keys)
        // Far fewer means the scan lost a shape of call or Sources moved, not that the app has fewer texts.
        #expect(used.count > 100, "found only \(used.count) keys in Sources")
        let missing = SourceStringKeys.missing(used.keys, from: english)
        let named = missing.map { "\"\($0)\" (\(used[$0] ?? "?"))" }
        #expect(named == [], "used in Sources but missing in en.lproj/Localizable.strings")
    }

    /// Whichever used key leaves en.lproj, the check above names exactly that key.
    @Test func removingAnyEnglishKeyIsNoticed() throws {
        let used = try SourceStringKeys.scan(Self.sources)
        let english = try Set(Self.strings("en").keys)
        var unnoticed: [String] = []
        for key in used.keys where english.contains(key) {
            let missing = SourceStringKeys.missing(used.keys, from: english.subtracting([key]))
            if missing != [key] { unnoticed.append(key) }
        }
        #expect(unnoticed.sorted() == [])
    }

    /// An exception the code no longer uses, or that English has by now, goes from the list.
    @Test func exceptionsAreStillNeeded() throws {
        let used = try SourceStringKeys.scan(Self.sources)
        let english = try Set(Self.strings("en").keys)
        for key in SourceStringKeys.sameInEveryLanguage.sorted() {
            #expect(used[key] != nil, "\"\(key)\" is no longer used in Sources")
            #expect(!english.contains(key), "\"\(key)\" is in en.lproj now")
        }
    }

    /// The Accessibility step every new user passes in setup (OnboardingSteps.swift).
    @Test(arguments: AppLanguage.all.map(\.code))
    func accessibilityStepIsTranslated(_ code: String) throws {
        let strings = try Self.strings(code)
        for key in [
            "Accessibility: allowed",
            "Accessibility: not yet allowed",
            "Turn on DockFlip in the list. This page notices it by itself.",
            "All set. Continue to the next step."
        ] {
            let value = try #require(strings[key], "\(code) lacks \"\(key)\"")
            #expect(!value.isEmpty)
            if code != "en" { #expect(value != key, "\(code) shows \"\(key)\" in English") }
        }
    }
}
