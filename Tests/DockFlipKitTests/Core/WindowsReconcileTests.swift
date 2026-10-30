import CoreGraphics
import Testing
@testable import DockFlipKit

@Suite("WindowsReconcile")
struct WindowsReconcileTests {
    @Test func aWindowThatDidNotAnswerIsKeptAndReadAgain() {
        // A failed read is not an answer: the known window stays, and the app is asked again.
        let plan = WindowsReconcile.after(listed: [(id: 1, isStandard: nil)], known: [1], inventory: [])
        #expect(plan == WindowsReconcile(gone: [], readAgain: true))
    }

    @Test func aWindowOnAnotherSpaceIsNotGone() {
        // kAXWindows lists only the current Space; the window server still knows window 2.
        let plan = WindowsReconcile.after(listed: [(id: 1, isStandard: true)], known: [1, 2], inventory: [2])
        #expect(plan == WindowsReconcile(gone: [], readAgain: false))
    }

    @Test func aWindowNobodyListsIsGone() {
        let plan = WindowsReconcile.after(listed: [(id: 1, isStandard: true)], known: [1, 2], inventory: [1])
        #expect(plan.gone == [2])
        #expect(!plan.readAgain)
    }

    @Test func aKnownWindowThatIsNoLongerStandardIsGone() {
        // It turned into a panel or a sheet, and the window server does not list it.
        let plan = WindowsReconcile.after(listed: [(id: 1, isStandard: false)], known: [1], inventory: [])
        #expect(plan.gone == [1])
    }

    @Test func anUnansweredWindowNotKnownBeforeIsNotAdopted() {
        // It is read again; whether it is gone is not this read's to say.
        let plan = WindowsReconcile.after(listed: [(id: 3, isStandard: nil)], known: [1], inventory: [1])
        #expect(plan == WindowsReconcile(gone: [], readAgain: true))
    }
}
