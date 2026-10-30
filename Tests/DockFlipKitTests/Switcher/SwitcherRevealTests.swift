import Testing
@testable import DockFlipKit

@Suite("SwitcherReveal")
struct SwitcherRevealTests {
    @Test func waitsLongEnoughForAQuickHop() {
        // ⌘Tab-Tab let go within 150 ms must switch before anything is drawn,
        // yet a deliberate hold must not wait noticeably (macOS and AltTab: 100–200 ms).
        #expect(SwitcherReveal.holdDelay >= .milliseconds(150))
        #expect(SwitcherReveal.holdDelay <= .milliseconds(200))
    }

    @Test func drawsWhileCommandIsHeld() {
        var selection = SwitcherSelection(count: 4, reverse: false)
        selection.step(1)
        #expect(SwitcherReveal.afterHold(selection: selection, query: "", commandHeld: true) == .draw)
    }

    @Test func fastHopReleasedBeforeTheHoldEndsSwitchesWithoutDrawing() {
        // ⌘Tab-Tab: two steps, ⌘ up but its release not handled yet when the hold ends.
        var selection = SwitcherSelection(count: 4, reverse: false)
        selection.step(1)
        #expect(SwitcherReveal.afterHold(selection: selection, query: "", commandHeld: false) == .open(2))
    }

    @Test func switchedOrCancelledDuringTheHoldDrawsNothing() {
        // The ⌘ release (or Esc) already closed the switcher: the timer finds no selection.
        #expect(SwitcherReveal.afterHold(selection: nil, query: "", commandHeld: false) == .closed)
        #expect(SwitcherReveal.afterHold(selection: nil, query: "", commandHeld: true) == .closed)
    }

    @Test func filterIsDrawnEvenAfterCommandIsUp() {
        // While filtering, releasing ⌘ does not switch (Return does), so the stack is drawn.
        let selection = SwitcherSelection(count: 4, reverse: false)
        #expect(SwitcherReveal.afterHold(selection: selection, query: "te", commandHeld: false) == .draw)
    }

    @Test func typingDrawsAtOnce() {
        #expect(SwitcherReveal.drawsAtOnce(query: "t"))
        #expect(!SwitcherReveal.drawsAtOnce(query: ""))
    }
}
