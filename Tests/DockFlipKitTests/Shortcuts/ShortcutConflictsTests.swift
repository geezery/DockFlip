import Testing
@testable import DockFlipKit

@Suite("ShortcutConflicts")
struct ShortcutConflictsTests {
    private let commandTab = HotkeyCommand.switcher(.commandTab(shift: false))
    private let commandShiftTab = HotkeyCommand.switcher(.commandTab(shift: true))

    @Test func rectangleDefaultsNameTheTakenShortcuts() {
        // Rectangle's defaults hold ⌃⌥ with the arrows, D and E.
        let failed: [HotkeyCommand] = [.snap(.left), .snap(.right), .snap(.up), .snap(.down), .showDesktop, .newFinderWindow]
        #expect(ShortcutConflicts.layoutShortcutNames(failed: failed) == ["⌃⌥←", "⌃⌥→", "⌃⌥↑", "⌃⌥↓", "⌃⌥D", "⌃⌥E"])
        let running = ["com.apple.finder", "com.knollsoft.Rectangle"]
        #expect(ShortcutConflicts.running(ShortcutConflicts.layoutApps, bundleIDs: running) == ["Rectangle"])
    }

    @Test func commandTabIsLeftToItsOwnLine() {
        #expect(ShortcutConflicts.layoutShortcutNames(failed: [commandTab, commandShiftTab]).isEmpty)
        #expect(ShortcutConflicts.layoutShortcutNames(failed: [commandTab, .showDesktop]) == ["⌃⌥D"])
    }

    @Test func nothingFailedSaysNothing() {
        #expect(ShortcutConflicts.layoutShortcutNames(failed: []).isEmpty)
    }

    @Test func allNineDockDigitsReadAsOne() {
        let digits = (0..<9).map { HotkeyCommand.dockItem($0) }
        #expect(ShortcutConflicts.layoutShortcutNames(failed: [.snap(.left)] + digits) == ["⌃⌥←", "⌃⌥1…9"])
        #expect(ShortcutConflicts.layoutShortcutNames(failed: [.dockItem(0), .dockItem(2)]) == ["⌃⌥1", "⌃⌥3"])
    }

    @Test func onlyRunningKnownAppsAreNamed() {
        #expect(ShortcutConflicts.running(ShortcutConflicts.layoutApps, bundleIDs: []).isEmpty)
        #expect(ShortcutConflicts.running(ShortcutConflicts.layoutApps, bundleIDs: ["com.lwouis.alt-tab-macos"]).isEmpty)
        let both = ["com.crowdcafe.windowmagnet", "com.knollsoft.Rectangle"]
        #expect(ShortcutConflicts.running(ShortcutConflicts.layoutApps, bundleIDs: both) == ["Rectangle", "Magnet"])
        #expect(ShortcutConflicts.running(ShortcutConflicts.commandTabApps, bundleIDs: ["com.lwouis.alt-tab-macos"]) == ["AltTab"])
    }
}
