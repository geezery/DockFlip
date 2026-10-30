import CoreGraphics
import Testing
@testable import DockFlipKit

@Suite("DockPress")
struct DockPressTests {
    private let start = CGPoint(x: 500, y: 1400)

    @Test func quickReleaseInPlaceIsAClick() {
        // Minimize / restore keeps working: a normal click stays DockFlip's.
        var press = DockPress(start: start, startTime: 10)
        #expect(press.released(at: start, at: 10.15) == .click)
    }

    @Test func smallWobbleIsStillAClick() {
        var press = DockPress(start: start, startTime: 10)
        let wobble = CGPoint(x: start.x + 2, y: start.y - 2)
        #expect(press.moved(to: wobble, at: 10.05) == .wait)
        #expect(press.released(at: wobble, at: 10.1) == .click)
    }

    @Test func dragHandsThePressToTheDock() {
        // Reordering or removing the icon: the Dock gets the press once, then everything after it.
        var press = DockPress(start: start, startTime: 10)
        let away = CGPoint(x: start.x + 12, y: start.y)
        #expect(press.moved(to: away, at: 10.1) == .handToDock)
        #expect(press.moved(to: CGPoint(x: start.x + 40, y: start.y - 30), at: 10.2) == .pass)
        #expect(press.released(at: start, at: 10.3) == .pass)
    }

    @Test func holdHandsThePressToTheDock() {
        // Press-and-hold opens the icon's menu: the timer hands the press over.
        var press = DockPress(start: start, startTime: 10)
        #expect(press.timerFired() == .handToDock)
        #expect(press.timerFired() == .pass)
        #expect(press.released(at: start, at: 11) == .pass)
    }

    @Test func slowReleaseIsTheDocksEvenBeforeTheTimer() {
        // A busy main thread can delay the timer past the mouse-up.
        var press = DockPress(start: start, startTime: 10)
        #expect(press.released(at: start, at: 10 + DockPress.holdLimit) == .handToDock)
    }

    @Test func releaseAwayFromThePressIsTheDocks() {
        // A quick flick off the icon without a drag event in between.
        var press = DockPress(start: start, startTime: 10)
        #expect(press.released(at: CGPoint(x: start.x, y: start.y - 20), at: 10.1) == .handToDock)
    }

    @Test func movingAfterTheHoldLimitIsTheDocks() {
        var press = DockPress(start: start, startTime: 10)
        #expect(press.moved(to: start, at: 10.6) == .handToDock)
    }
}
