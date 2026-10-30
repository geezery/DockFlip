import Testing
@testable import DockFlipKit

@Suite("QuitFollowUp")
struct QuitFollowUpTests {
    private func check(asked: Bool = true, terminated: Bool = false, hidden: Bool = false, active: Bool = false) -> QuitFollowUp.Check {
        QuitFollowUp.Check(wasAsked: asked, isTerminated: terminated, isHidden: hidden, isActive: active)
    }

    @Test func quitAppNeedsNothing() {
        #expect(QuitFollowUp.after(check(terminated: true)) == .done)
        #expect(QuitFollowUp.after(check(terminated: true, hidden: true)) == .done)
    }

    @Test func hiddenAppStillRunningComesForward() {
        // TextEdit with an unsaved, hidden document: its review-changes question is invisible.
        #expect(QuitFollowUp.after(check(hidden: true)) == .bringForward)
        #expect(QuitFollowUp.after(check(hidden: true, active: true)) == .bringForward)
    }

    @Test func backgroundAppStillRunningComesForward() {
        #expect(QuitFollowUp.after(check()) == .bringForward)
    }

    @Test func frontVisibleAppIsLeftAlone() {
        #expect(QuitFollowUp.after(check(active: true)) == .done)
    }

    @Test func requestThatNeverReachedTheAppIsLeftAlone() {
        #expect(QuitFollowUp.after(check(asked: false)) == .done)
        #expect(QuitFollowUp.after(check(asked: false, hidden: true)) == .done)
    }
}
