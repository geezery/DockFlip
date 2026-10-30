import Foundation
import Testing
@testable import DockFlipKit

@Suite("SelfCheck")
struct SelfCheckTests {
    private func lines(_ check: SelfCheck, commandTabSwitchFound: Bool = true) -> [String] {
        check.lines(commandTabSwitchFound: commandTabSwitchFound)
    }

    @Test func nothingSeenYetBlamesNothing() {
        #expect(lines(SelfCheck()) == [
            "⌘Tab switch-off, CGSSetSymbolicHotKeyEnabled: found, not used yet",
            "Window ids, _AXUIElementGetWindow: not tried yet: no window read",
            "Windows on other Spaces, _AXUIElementCreateWithRemoteToken: not tried yet: no window on another Space or in full screen",
            "Dock hover, AX observer on the Dock: not tried yet"
        ])
    }

    /// A macOS without the private call keeps its own ⌘Tab on beside DockFlip's.
    @Test func missingCommandTabSwitchIsNamed() {
        #expect(lines(SelfCheck(), commandTabSwitchFound: false)[0]
                == "⌘Tab switch-off, CGSSetSymbolicHotKeyEnabled: MISSING: macOS's own ⌘Tab stays on")
    }

    @Test func commandTabSwitchFailsOnlyWhenNoCallWorked() {
        var check = SelfCheck()
        check.commandTabSwitch.record(false, error: 1000)
        check.commandTabSwitch.record(false, error: 1001)
        #expect(lines(check)[0] == "⌘Tab switch-off, CGSSetSymbolicHotKeyEnabled: FAILED, 0 of 2 calls, last error 1001: macOS's own ⌘Tab stays on")
        check.commandTabSwitch.record(true, error: 0)
        #expect(lines(check)[0] == "⌘Tab switch-off, CGSSetSymbolicHotKeyEnabled: ok, 1 of 3 calls, last error 1001")
    }

    /// A window that closes while it is read fails too: one window that answered is enough.
    @Test func windowIDsFailOnlyWhenNoWindowAnswered() {
        var check = SelfCheck()
        check.windowIDs.record(false, error: -25202)
        #expect(lines(check)[1] == "Window ids, _AXUIElementGetWindow: FAILED, 0 of 1 window, last error -25202: DockFlip sees no windows")
        check.windowIDs.record(true, error: 0)
        check.windowIDs.record(true, error: 0)
        #expect(lines(check)[1] == "Window ids, _AXUIElementGetWindow: ok, 2 of 3 windows, last error -25202")

        var clean = SelfCheck()
        clean.windowIDs.record(true, error: 0)
        #expect(lines(clean)[1] == "Window ids, _AXUIElementGetWindow: ok, 1 of 1 window")
    }

    @Test func walkThatReachesNoElementFails() {
        var check = SelfCheck()
        check.walk.record(sought: 2, found: 0, answered: 0)
        #expect(lines(check)[2] == "Windows on other Spaces, _AXUIElementCreateWithRemoteToken: FAILED, no element answered in 1 search: windows on other Spaces and in full screen are missed")
    }

    /// Elements answering but no window found can be a big app outlasting the time
    /// budget: flagged, not failed; one window found is ok.
    @Test func walkThatFindsNothingIsFlaggedUntilOneIsFound() {
        var check = SelfCheck()
        check.walk.record(sought: 2, found: 0, answered: 40)
        check.walk.record(sought: 3, found: 0, answered: 12)
        #expect(lines(check)[2] == "Windows on other Spaces, _AXUIElementCreateWithRemoteToken: NONE FOUND, 0 of 5 windows in 2 searches")
        check.walk.record(sought: 1, found: 1, answered: 3)
        #expect(lines(check)[2] == "Windows on other Spaces, _AXUIElementCreateWithRemoteToken: ok, 1 of 6 windows found in 3 searches")
    }

    @Test func dockFailureSaysWhy() {
        var check = SelfCheck()
        check.recordDock(.failed("Dock list not found"))
        #expect(lines(check)[3] == "Dock hover, AX observer on the Dock: FAILED, Dock list not found: no window list on hover")
    }

    /// Attached is not enough: a Dock that never reports a hover is silent.
    @Test func dockHoversCountFromTheLatestAttach() {
        var check = SelfCheck()
        check.recordDock(.attached)
        #expect(lines(check)[3] == "Dock hover, AX observer on the Dock: attached, no hover reported yet: silent if the mouse has rested on a Dock icon")
        check.dockHovers += 1
        #expect(lines(check)[3] == "Dock hover, AX observer on the Dock: ok, 1 hover change since attached")
        check.dockHovers += 1
        #expect(lines(check)[3] == "Dock hover, AX observer on the Dock: ok, 2 hover changes since attached")
        // The Dock restarts after its settings change: a new Dock that stays silent must show.
        check.recordDock(.attached)
        #expect(check.dockHovers == 0)
    }

    /// The search for windows on other Spaces reports to the self-check. No ids:
    /// no Accessibility call is made, only the record.
    @Test func searchesForWindowsElsewhereAreRecorded() {
        let before = SelfCheck.current.walk.searches
        _ = WindowServer.findWindows(pid: getpid(), ids: [], budget: 0)
        #expect(SelfCheck.current.walk.searches > before)
    }

    /// The private call that turns macOS's own ⌘Tab off, on the macOS CI runs: a
    /// macOS that drops it fails here before a user's bug report says so.
    @Test func commandTabSwitchExistsOnThisMacOS() {
        #expect(NativeCommandTab.isAvailable)
    }
}
