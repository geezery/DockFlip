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

    @Test func settingsWarnsWhenAltTabHoldsCommandTab() {
        let warning = ShortcutConflicts.warning(commandTabHeld: true, layoutHeld: [],
                                                bundleIDs: ["com.lwouis.alt-tab-macos", "com.knollsoft.Rectangle"])
        // Rectangle runs but holds nothing of ours: only AltTab is named.
        #expect(warning == ShortcutConflicts.Warning(shortcuts: ["⌘Tab"], apps: ["AltTab"]))
    }

    @Test func settingsWarningNamesCommandTabFirstThenTheLayoutKeys() {
        let warning = ShortcutConflicts.warning(commandTabHeld: true, layoutHeld: ["⌃⌥←", "⌃⌥D"],
                                                bundleIDs: ["com.knollsoft.Rectangle", "com.lwouis.alt-tab-macos"])
        #expect(warning == ShortcutConflicts.Warning(shortcuts: ["⌘Tab", "⌃⌥←", "⌃⌥D"], apps: ["AltTab", "Rectangle"]))
        let unknown = ShortcutConflicts.warning(commandTabHeld: false, layoutHeld: ["⌃⌥←"], bundleIDs: [])
        #expect(unknown == ShortcutConflicts.Warning(shortcuts: ["⌃⌥←"], apps: []))
    }

    @Test func settingsWarningClearsOnceDockFlipHoldsEverything() {
        // After the other app quits and Try Again succeeds, nothing is held elsewhere.
        #expect(ShortcutConflicts.warning(commandTabHeld: false, layoutHeld: [],
                                          bundleIDs: ["com.lwouis.alt-tab-macos"]) == nil)
    }

    @Test func onlyRunningKnownAppsAreNamed() {
        #expect(ShortcutConflicts.running(ShortcutConflicts.layoutApps, bundleIDs: []).isEmpty)
        #expect(ShortcutConflicts.running(ShortcutConflicts.layoutApps, bundleIDs: ["com.lwouis.alt-tab-macos"]).isEmpty)
        let both = ["com.crowdcafe.windowmagnet", "com.knollsoft.Rectangle"]
        #expect(ShortcutConflicts.running(ShortcutConflicts.layoutApps, bundleIDs: both) == ["Rectangle", "Magnet"])
        #expect(ShortcutConflicts.running(ShortcutConflicts.commandTabApps, bundleIDs: ["com.lwouis.alt-tab-macos"]) == ["AltTab"])
    }
}
