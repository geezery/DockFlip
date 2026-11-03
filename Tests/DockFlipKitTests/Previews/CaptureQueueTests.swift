import Testing
@testable import DockFlipKit

/// At most a few captures run together; the rest wait their turn.
/// (Mutating calls stay outside `#expect`, which cannot call them.)
@Suite("Thumbnails: capture queue")
struct CaptureQueueTests {
    @Test func startsUpToTheLimitThenWaits() {
        var queue = CaptureQueue<Int>(limit: 3)
        let started = (1...5).map { queue.request($0, urgent: false) }
        #expect(started == [true, true, true, false, false])
        #expect(queue.running == [1, 2, 3])
        #expect(queue.waiting == [4, 5])
    }

    @Test func aFinishedCaptureHandsItsTurnOnInOrder() {
        var queue = CaptureQueue<Int>(limit: 1)
        _ = queue.request(1, urgent: false)
        _ = queue.request(2, urgent: false)
        _ = queue.request(3, urgent: false)
        let afterFirst = queue.finish(1)
        let afterSecond = queue.finish(2)
        let afterThird = queue.finish(3)
        #expect(afterFirst == [2])
        #expect(afterSecond == [3])
        #expect(afterThird == [])
        #expect(queue.running.isEmpty)
    }

    @Test func urgentCapturesJumpTheLine() {
        var queue = CaptureQueue<Int>(limit: 1)
        _ = queue.request(1, urgent: false)
        _ = queue.request(2, urgent: false)
        _ = queue.request(3, urgent: true)
        #expect(queue.waiting == [3, 2])
        _ = queue.request(4, urgent: false)
        queue.promote(4)
        #expect(queue.waiting == [4, 3, 2])
        // Promoting one running or never asked for changes nothing.
        queue.promote(1)
        queue.promote(9)
        #expect(queue.waiting == [4, 3, 2])
    }

    @Test func askingTwiceDoesNotQueueTwice() {
        var queue = CaptureQueue<Int>(limit: 1)
        let first = queue.request(1, urgent: false)
        let again = queue.request(1, urgent: false)
        _ = queue.request(2, urgent: false)
        let urgentAgain = queue.request(2, urgent: true)
        #expect(first)
        #expect(!again)
        #expect(!urgentAgain)
        #expect(queue.waiting == [2])
    }
}
