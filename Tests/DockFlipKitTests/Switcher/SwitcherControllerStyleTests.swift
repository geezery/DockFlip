import CoreGraphics
import Testing
@testable import DockFlipKit

/// The ⌘Tab look (Flip 3D or the Windows 11 grid) is read as the switcher opens,
/// and the grid switches exactly as the stack does.
@Suite("SwitcherController: style")
@MainActor
struct SwitcherControllerStyleTests {
    @MainActor
    final class StyleSource {
        var style: SwitcherStyle
        var reads = 0
        /// Looks the switcher's toggle saved.
        var saved: [SwitcherStyle] = []
        var managed = false
        init(_ style: SwitcherStyle) { self.style = style }
    }

    private func makeSwitcher(
        _ mac: SwitcherControllerTests.FakeMac, style: StyleSource
    ) -> (SwitcherController, SwitcherControllerTests.FakePresenter) {
        let presenter = SwitcherControllerTests.FakePresenter()
        let switcher = SwitcherController(
            switcherWindows: { mac.windows },
            focusWindow: { mac.focused.append($0) },
            isCommandHeld: { mac.commandHeld },
            sleep: { mac.slept.append($0) },
            style: { style.reads += 1; return style.style },
            setStyle: { style.saved.append($0); style.style = $0 },
            canChangeStyle: { !style.managed },
            presenter: presenter
        )
        return (switcher, presenter)
    }

    @Test func gridOpensStepsAndSwitchesLikeTheStack() {
        let mac = SwitcherControllerTests.FakeMac(windowIDs: [10, 20, 30], commandHeld: true)
        let style = StyleSource(.grid)
        let (switcher, presenter) = makeSwitcher(mac, style: style)

        switcher.handle(.commandTab(shift: false))
        switcher.handle(.commandTab(shift: false))
        mac.commandHeld = false
        switcher.handle(.commandReleased)

        #expect(mac.focused == [30])
        #expect(presenter.shown == 1)
        #expect(presenter.hidden == [false])
        // Read once as it opened, not on every step.
        #expect(style.reads == 1)
    }

    @Test func aStyleChangeShowsFromTheNextCommandTab() {
        let mac = SwitcherControllerTests.FakeMac(windowIDs: [10, 20], commandHeld: false)
        let style = StyleSource(.flip3D)
        let (switcher, _) = makeSwitcher(mac, style: style)

        switcher.handle(.commandTab(shift: false))
        style.style = .grid
        switcher.handle(.commandTab(shift: false))

        // Each quick ⌘Tab hops to the previous window, whatever the look.
        #expect(mac.focused == [20, 20])
        #expect(style.reads == 2)
    }

    @Test func theToggleChangesTheLookWhileOpenAndKeepsIt() {
        let mac = SwitcherControllerTests.FakeMac(windowIDs: [10, 20, 30], commandHeld: true)
        let style = StyleSource(.flip3D)
        let (switcher, presenter) = makeSwitcher(mac, style: style)

        switcher.handle(.commandTab(shift: false))
        switcher.handle(.commandTab(shift: false))
        switcher.changeStyle(to: .grid)

        // Still open, on the same window, and saved as the Settings choice.
        #expect(switcher.isActive)
        #expect(presenter.hidden == [])
        #expect(style.saved == [.grid])
        mac.commandHeld = false
        switcher.handle(.commandReleased)
        #expect(mac.focused == [30])

        // The next ⌘Tab opens in the look picked.
        mac.commandHeld = true
        switcher.handle(.commandTab(shift: false))
        #expect(style.reads == 2)
        #expect(style.style == .grid)
    }

    @Test func theToggleSavesNothingForTheSameLookOrWhenClosed() {
        let mac = SwitcherControllerTests.FakeMac(windowIDs: [10, 20], commandHeld: true)
        let style = StyleSource(.grid)
        let (switcher, _) = makeSwitcher(mac, style: style)

        switcher.changeStyle(to: .flip3D) // closed
        switcher.handle(.commandTab(shift: false))
        switcher.changeStyle(to: .grid) // already the look

        #expect(style.saved == [])
    }

    @Test func aManagedLookCannotBeChangedFromTheSwitcher() {
        let mac = SwitcherControllerTests.FakeMac(windowIDs: [10, 20], commandHeld: true)
        let style = StyleSource(.flip3D)
        style.managed = true
        let (switcher, _) = makeSwitcher(mac, style: style)

        switcher.handle(.commandTab(shift: false))
        switcher.changeStyle(to: .grid)

        #expect(style.saved == [])
        #expect(switcher.isActive)
    }
}
