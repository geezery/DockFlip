import ApplicationServices
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

    @Test func readOnTheAppsQueueBecomesACheck() {
        // The registry no longer tracks it, or the element is destroyed: gone.
        #expect(CloseFollowUp.Check(isTracked: false, read: .init(error: .success)) == check(gone: true))
        #expect(CloseFollowUp.Check(isTracked: true, read: .init(error: .invalidUIElement)) == check(gone: true))
        // Still there and answering: its sheet and minimized state count.
        #expect(CloseFollowUp.Check(isTracked: true, read: .init(error: .success, hasSheet: true, isMinimized: true))
                == check(sheet: true, minimized: true))
    }

    @Test func timedOutReadIsNoAnswer() {
        // A hung app's timeout says nothing about sheets: it is not taken as "asking".
        let read = CloseFollowUp.Read(error: .cannotComplete, hasSheet: true, isMinimized: true)
        #expect(CloseFollowUp.Check(isTracked: true, read: read) == check(answered: false))
    }
}
