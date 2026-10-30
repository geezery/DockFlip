import Testing
@testable import DockFlipKit

@Suite("CloseFollowUp")
struct CloseFollowUpTests {
    private func check(gone: Bool = false, answered: Bool = true, sheet: Bool = false, minimized: Bool = false) -> CloseFollowUp.Check {
        CloseFollowUp.Check(isGone: gone, answered: answered, hasSheet: sheet, isMinimized: minimized)
    }

    @Test func closedWindowNeedsNothing() {
        #expect(CloseFollowUp.after(check(gone: true), isLastLook: false) == .done)
        #expect(CloseFollowUp.after(check(gone: true, sheet: true, minimized: true), isLastLook: false) == .done)
    }

    @Test func saveSheetComesForward() {
        // Minimized, behind others or on another desktop: wherever it is, a sheet brings it forward.
        #expect(CloseFollowUp.after(check(sheet: true), isLastLook: false) == .bringForward)
        #expect(CloseFollowUp.after(check(sheet: true, minimized: true), isLastLook: true) == .bringForward)
    }

    @Test func minimizedWindowThatStayedComesForward() {
        #expect(CloseFollowUp.after(check(minimized: true), isLastLook: false) == .bringForward)
    }

    @Test func visibleWindowWithoutSheetIsLeftAlone() {
        #expect(CloseFollowUp.after(check(), isLastLook: false) == .done)
    }

    @Test func busyAppIsAskedOnceMore() {
        #expect(CloseFollowUp.after(check(answered: false), isLastLook: false) == .lookAgain)
        #expect(CloseFollowUp.after(check(answered: false), isLastLook: true) == .done)
    }
}
