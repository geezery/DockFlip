import CoreGraphics
import Testing
@testable import DockFlipKit

@Suite("SnapRestoreFrames")
struct SnapRestoreFramesTests {
    let frame = CGRect(x: 100, y: 100, width: 800, height: 600)

    @Test func closedWindowsAreDroppedOnTheNextWrite() {
        var frames = SnapRestoreFrames()
        var live: [CGWindowID] = []
        // Snap and close 100 windows, one after another.
        for id in CGWindowID(1)...100 {
            live.append(id)
            frames.remember(frame, for: id, live: live)
            live.removeAll { $0 == id }
        }
        let afterClosing = frames.frames.count
        #expect(afterClosing == 1)

        live = [200, 201]
        frames.remember(frame, for: 200, live: live)
        frames.remember(frame, for: 201, live: live)
        let keys = Set(frames.frames.keys)
        #expect(keys == [200, 201])
    }

    @Test func takeHandsTheFrameBackOnce() {
        var frames = SnapRestoreFrames()
        frames.remember(frame, for: 7, live: [7])
        let first = frames.take(7)
        let second = frames.take(7)
        #expect(first == frame)
        #expect(second == nil)
    }

    @Test func theSnappedWindowIsKeptEvenIfNotYetListed() {
        var frames = SnapRestoreFrames()
        frames.remember(frame, for: 9, live: [CGWindowID]())
        let kept = frames[9]
        #expect(kept == frame)
    }
}
