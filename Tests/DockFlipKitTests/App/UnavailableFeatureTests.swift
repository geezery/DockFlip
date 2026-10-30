import Testing
@testable import DockFlipKit

/// The menu bar menu names a feature a new macOS broke, and only that: a line that
/// blames macOS by mistake would cost more trust than the line earns.
@Suite("UnavailableFeature")
struct UnavailableFeatureTests {
    private func list(_ check: SelfCheck, accessibilityAllowed: Bool = true,
                      commandTabSwitchFound: Bool = true, ownsCommandTab: Bool = true) -> [UnavailableFeature] {
        UnavailableFeature.list(check, accessibilityAllowed: accessibilityAllowed,
                                commandTabSwitchFound: commandTabSwitchFound, ownsCommandTab: ownsCommandTab)
    }

    /// Every hook broken at once, as a macOS that changed them all would leave it.
    private var allBroken: SelfCheck {
        var check = SelfCheck()
        check.commandTabSwitch.record(false, error: 1000)
        check.windowIDs.record(false, error: -25202)
        check.walk.record(sought: 2, found: 0, answered: 0)
        check.recordDock(.failed("Dock list not found"))
        return check
    }

    @Test func nothingSeenYetBlamesNothing() {
        #expect(list(SelfCheck()) == [])
    }

    @Test func eachFailureNamesItsFeature() {
        #expect(list(SelfCheck(), commandTabSwitchFound: false) == [.commandTabSwitchOff])

        var switchFailed = SelfCheck()
        switchFailed.commandTabSwitch.record(false, error: 1000)
        #expect(list(switchFailed) == [.commandTabSwitchOff])

        var windowsFailed = SelfCheck()
        windowsFailed.windowIDs.record(false, error: -25202)
        #expect(list(windowsFailed) == [.windowTracking])

        var walkFailed = SelfCheck()
        walkFailed.walk.record(sought: 2, found: 0, answered: 0)
        #expect(list(walkFailed) == [.otherSpaces])

        var dockFailed = SelfCheck()
        dockFailed.recordDock(.failed("could not observe the Dock"))
        #expect(list(dockFailed) == [.dockLists])

        #expect(list(allBroken) == [.commandTabSwitchOff, .windowTracking, .otherSpaces, .dockLists])
    }

    /// What the debug log calls "ok", "attached, no hover" or "NONE FOUND" can be the
    /// user's own doing (no hover yet, a closing window, a big app outlasting the
    /// time budget), so the menu stays quiet about it.
    @Test func partOrUnprovenFailureIsNotBlamed() {
        var check = SelfCheck()
        check.commandTabSwitch.record(false, error: 1000)
        check.commandTabSwitch.record(true, error: 0)
        check.windowIDs.record(false, error: -25202)
        check.windowIDs.record(true, error: 0)
        check.walk.record(sought: 3, found: 0, answered: 40)
        check.recordDock(.attached)
        #expect(list(check) == [])
    }

    /// Whoever turned DockFlip's shortcuts off, or lets AltTab have ⌘Tab, wants
    /// macOS's own ⌘Tab on, and a call that gives it back doesn't count.
    @Test func commandTabSwitchOnlyWhileDockFlipHoldsCommandTab() {
        #expect(list(SelfCheck(), commandTabSwitchFound: false, ownsCommandTab: false) == [])
        #expect(list(allBroken, ownsCommandTab: false) == [.windowTracking, .otherSpaces, .dockLists])
    }

    /// Without Accessibility every call fails, and the menu offers Grant Accessibility.
    @Test func withoutAccessibilityNothingIsBlamedOnMacOS() {
        #expect(list(allBroken, accessibilityAllowed: false, commandTabSwitchFound: false) == [])
    }

    /// The menu and the debug log's Self-check section never disagree: a feature is
    /// listed exactly when its log line says FAILED or MISSING.
    @Test(arguments: [false, true])
    func matchesTheDebugLog(commandTabSwitchFound: Bool) {
        var walkNoneFound = SelfCheck()
        walkNoneFound.walk.record(sought: 1, found: 0, answered: 5)
        var dockSilent = SelfCheck()
        dockSilent.recordDock(.attached)
        var recovered = allBroken
        recovered.commandTabSwitch.record(true, error: 0)
        recovered.windowIDs.record(true, error: 0)
        recovered.walk.record(sought: 1, found: 1, answered: 3)
        recovered.recordDock(.attached)

        for check in [SelfCheck(), allBroken, walkNoneFound, dockSilent, recovered] {
            let lines = check.lines(commandTabSwitchFound: commandTabSwitchFound)
            let features = list(check, commandTabSwitchFound: commandTabSwitchFound)
            #expect(lines.count == UnavailableFeature.allCases.count)
            for (line, feature) in zip(lines, UnavailableFeature.allCases) {
                let failed = line.contains("FAILED") || line.contains("MISSING")
                #expect(features.contains(feature) == failed, "\(line)")
            }
        }
    }
}
