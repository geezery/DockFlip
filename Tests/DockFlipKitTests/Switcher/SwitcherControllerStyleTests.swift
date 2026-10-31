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
}
