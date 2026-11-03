import Testing
@testable import DockFlipKit

/// At most a few captures run together; the rest wait their turn.
@Suite("Thumbnails: capture queue")
struct CaptureQueueTests {
    @Test func startsUpToTheLimitThenWaits() {
        var queue = CaptureQueue<Int>(limit: 3)
        #expect(queue.request(1, urgent: false))
        #expect(queue.request(2, urgent: false))
        #expect(queue.request(3, urgent: false))
        #expect(!queue.request(4, urgent: false))
        #expect(!queue.request(5, urgent: false))
        #expect(queue.running == [1, 2, 3])
        #expect(queue.waiting == [4, 5])
    }

    @Test func aFinishedCaptureHandsItsTurnOnInOrder() {
        var queue = CaptureQueue<Int>(limit: 1)
        _ = queue.request(1, urgent: false)
        _ = queue.request(2, urgent: false)
        _ = queue.request(3, urgent: false)
        #expect(queue.finish(1) == [2])
        #expect(queue.finish(2) == [3])
        #expect(queue.finish(3) == [])
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
        #expect(queue.request(1, urgent: false))
        #expect(!queue.request(1, urgent: false))
        _ = queue.request(2, urgent: false)
        #expect(!queue.request(2, urgent: true))
        #expect(queue.waiting == [2])
    }
}
