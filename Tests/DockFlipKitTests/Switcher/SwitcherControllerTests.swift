import CoreGraphics
import Testing
@testable import DockFlipKit

/// The ⌘Tab flow end to end: open, step, release, filter, cancel. `FakeMac` stands in
/// for the window registry, the live ⌘ state and the hold; `FakePresenter` for the panel.
@Suite("SwitcherController")
@MainActor
struct SwitcherControllerTests {
    @MainActor
    final class FakeMac {
        var windows: [WindowSnapshot]
        var commandHeld: Bool
        var focused: [CGWindowID] = []
        var slept: [Duration] = []

        init(windowIDs: [CGWindowID], commandHeld: Bool) {
            windows = windowIDs.map { id in
                WindowSnapshot(
                    id: id, pid: 1, bundleID: "test.app\(id)", appName: "App \(id)", icon: nil,
                    title: "Window \(id)", frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                    isMinimized: false, isAppHidden: false
                )
            }
            self.commandHeld = commandHeld
        }
    }

    @MainActor
    final class FakePresenter: SwitcherPresenter {
        var onInput: ((SwitcherInput) -> Void)?
        var shown = 0
        var drawn = 0
        /// One entry per hide: whether it went back to the previous app.
        var hidden: [Bool] = []

        func show() { shown += 1 }
        func draw() { drawn += 1 }
        func hide(returningToPreviousApp: Bool) { hidden.append(returningToPreviousApp) }
    }

    private func makeSwitcher(_ mac: FakeMac) -> (SwitcherController, FakePresenter) {
        let presenter = FakePresenter()
        let switcher = SwitcherController(
            switcherWindows: { mac.windows },
            focusWindow: { mac.focused.append($0) },
            isCommandHeld: { mac.commandHeld },
            sleep: { mac.slept.append($0) },
            presenter: presenter
        )
        return (switcher, presenter)
    }

    @Test func quickCommandTabFocusesThePreviousWindowWithoutAPanel() {
        // ⌘ was let go before the hot key was handled: no release event follows.
        let mac = FakeMac(windowIDs: [10, 20, 30], commandHeld: false)
        let (switcher, presenter) = makeSwitcher(mac)

        #expect(switcher.handle(.commandTab(shift: false)))

        #expect(mac.focused == [20])
        #expect(presenter.shown == 0)
        #expect(presenter.drawn == 0)
        #expect(!switcher.isActive)
        #expect(switcher.revealTask == nil)
    }

    @Test func quickCommandShiftTabFocusesTheLastWindow() {
        let mac = FakeMac(windowIDs: [10, 20, 30], commandHeld: false)
        let (switcher, presenter) = makeSwitcher(mac)

        switcher.handle(.commandTab(shift: true))

        #expect(mac.focused == [30])
        #expect(presenter.shown == 0)
    }

    @Test func heldCommandOpensAndReleaseFocusesTheSelectedWindow() {
        let mac = FakeMac(windowIDs: [10, 20, 30], commandHeld: true)
        let (switcher, presenter) = makeSwitcher(mac)
        var active: [Bool] = []
        switcher.onActiveChanged = { active.append($0) }

        #expect(switcher.handle(.commandTab(shift: false)))
        #expect(switcher.isActive)
        #expect(presenter.shown == 1)
        #expect(presenter.drawn == 0) // drawn only after the hold
        #expect(mac.focused.isEmpty)

        switcher.handle(.commandTab(shift: false))
        mac.commandHeld = false
        // The release is passed on, not swallowed: other apps see ⌘ go up.
        #expect(!switcher.handle(.commandReleased))

        #expect(mac.focused == [30])
        #expect(presenter.hidden == [false])
        #expect(!switcher.isActive)
        #expect(active == [true, false])
    }

    @Test func nextAndPreviousStepOnlyWhileOpen() {
        let mac = FakeMac(windowIDs: [10, 20, 30], commandHeld: true)
        let (switcher, _) = makeSwitcher(mac)
        #expect(!switcher.handle(.next))
        #expect(!switcher.handle(.previous))

        switcher.handle(.commandTab(shift: false)) // selects 20
        #expect(switcher.handle(.next))            // 30
        #expect(switcher.handle(.previous))        // 20
        #expect(switcher.handle(.previous))        // 10
        mac.commandHeld = false
        switcher.handle(.commandReleased)

        #expect(mac.focused == [10])
    }

    @Test func keysFromThePanelReachTheController() {
        let mac = FakeMac(windowIDs: [10, 20, 30], commandHeld: true)
        let (switcher, presenter) = makeSwitcher(mac)
        switcher.handle(.commandTab(shift: false))

        presenter.onInput?(.previous)
        presenter.onInput?(.commandReleased)

        #expect(mac.focused == [10])
    }

    @Test func holdDrawsTheSwitcherWhileCommandIsHeld() async {
        let mac = FakeMac(windowIDs: [10, 20], commandHeld: true)
        let (switcher, presenter) = makeSwitcher(mac)
        switcher.handle(.commandTab(shift: false))

        await switcher.revealTask?.value

        #expect(mac.slept == [SwitcherReveal.holdDelay])
        #expect(presenter.drawn == 1)
        #expect(switcher.isActive)
        #expect(mac.focused.isEmpty)
    }

    @Test func commandLetGoDuringTheHoldSwitchesWithoutDrawing() async {
        // ⌘ went up during the hold but its release has not reached DockFlip yet.
        let mac = FakeMac(windowIDs: [10, 20], commandHeld: true)
        let (switcher, presenter) = makeSwitcher(mac)
        switcher.handle(.commandTab(shift: false))
        mac.commandHeld = false

        await switcher.revealTask?.value

        #expect(mac.focused == [20])
        #expect(presenter.drawn == 0)
        #expect(!switcher.isActive)
    }

    @Test func filterDrawsAtOnceAndWaitsForReturn() {
        let mac = FakeMac(windowIDs: [10, 20, 30], commandHeld: true)
        let (switcher, presenter) = makeSwitcher(mac)
        switcher.handle(.commandTab(shift: false))

        #expect(switcher.handle(.text("30")))
        #expect(presenter.drawn == 1)
        mac.commandHeld = false
        switcher.handle(.commandReleased)
        #expect(mac.focused.isEmpty)
        #expect(switcher.isActive)

        #expect(switcher.handle(.enter))
        #expect(mac.focused == [30])
    }

    @Test func modifierAfterClearingTheFilterDoesNotSwitch() {
        let mac = FakeMac(windowIDs: [10, 20, 30], commandHeld: true)
        let (switcher, presenter) = makeSwitcher(mac)
        switcher.handle(.commandTab(shift: false))
        switcher.handle(.text("20"))
        mac.commandHeld = false
        switcher.handle(.commandReleased)   // ⌘ up while filtering: no switch
        #expect(switcher.handle(.escape))    // filter cleared, the stack stays open

        // ⇧, ⌃ or ⌥ pressed now sends a flags change without ⌘, like a release.
        switcher.handle(.commandReleased)
        #expect(switcher.isActive)
        #expect(mac.focused.isEmpty)
        #expect(presenter.hidden.isEmpty)

        #expect(switcher.handle(.commandTab(shift: true))) // ⇧Tab: from 10 back to 30
        switcher.handle(.commandReleased)                  // ⇧ let go
        #expect(mac.focused.isEmpty)
        #expect(switcher.handle(.enter))
        #expect(mac.focused == [30])
    }

    @Test func modifierAfterBackspacingTheFilterDoesNotSwitch() {
        let mac = FakeMac(windowIDs: [10, 20, 30], commandHeld: true)
        let (switcher, _) = makeSwitcher(mac)
        switcher.handle(.commandTab(shift: false))
        switcher.handle(.text("2"))
        mac.commandHeld = false
        switcher.handle(.commandReleased)
        #expect(switcher.handle(.deleteBackward))

        switcher.handle(.commandReleased)

        #expect(switcher.isActive)
        #expect(mac.focused.isEmpty)
    }

    @Test func escapeClearsTheFilterFirstThenGoesBack() {
        let mac = FakeMac(windowIDs: [10, 20, 30], commandHeld: true)
        let (switcher, presenter) = makeSwitcher(mac)
        switcher.handle(.commandTab(shift: false))
        switcher.handle(.text("x"))

        #expect(switcher.handle(.escape))
        #expect(switcher.isActive)

        #expect(switcher.handle(.escape))
        #expect(!switcher.isActive)
        #expect(presenter.hidden == [true])
        #expect(mac.focused.isEmpty)
    }

    @Test func noWindowsOpensNothing() {
        let mac = FakeMac(windowIDs: [], commandHeld: true)
        let (switcher, presenter) = makeSwitcher(mac)

        #expect(!switcher.handle(.commandTab(shift: false)))
        #expect(presenter.shown == 0)
        #expect(!switcher.isActive)
    }

    @Test func lateReleaseAfterSwitchingDoesNothing() {
        let mac = FakeMac(windowIDs: [10, 20], commandHeld: false)
        let (switcher, presenter) = makeSwitcher(mac)
        switcher.handle(.commandTab(shift: false))

        switcher.handle(.commandReleased)

        #expect(mac.focused == [20])
        #expect(presenter.hidden.count == 1)
    }
}
