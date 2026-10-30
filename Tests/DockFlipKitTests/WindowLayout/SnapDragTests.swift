import CoreGraphics
import Testing
@testable import DockFlipKit

@Suite("SnapDrag")
struct SnapDragTests {
    // Pressed at `start` (Cocoa space) on the title bar of window 42 at `frame` (AX space).
    let start = CGPoint(x: 500, y: 700)
    let frame = CGRect(x: 100, y: 200, width: 800, height: 600)

    /// Where the window is when it follows the mouse to `mouse`: Cocoa's y grows
    /// upwards, AX's downwards.
    func following(_ mouse: CGPoint) -> CGRect {
        frame.offsetBy(dx: mouse.x - start.x, dy: start.y - mouse.y)
    }

    @Test func plainClickLooksNothingUp() {
        var drag = SnapDrag(startMouse: start)
        var listReads = 0
        var frameReads = 0
        // A click with a little jitter: drag events, all within the threshold.
        for mouse in [CGPoint(x: 501, y: 700), CGPoint(x: 503, y: 698), CGPoint(x: 505, y: 694)] {
            drag.moved(to: mouse, windowUnder: { _ in listReads += 1; return (42, frame) },
                       frame: { _ in frameReads += 1; return frame })
        }
        #expect(listReads == 0)
        #expect(frameReads == 0)
        #expect(drag.phase == .pressed)
        #expect(drag.window?.id == nil)
    }

    @Test func titleBarDragBecomesWindowDragWithItsStartFrame() {
        var drag = SnapDrag(startMouse: start)
        var listReads = 0
        var frameReads = 0
        let path = [CGPoint(x: 504, y: 698), CGPoint(x: 510, y: 694), CGPoint(x: 520, y: 688),
                    CGPoint(x: 300, y: 600), CGPoint(x: 2, y: 500)]
        for mouse in path {
            drag.moved(to: mouse, windowUnder: { point in
                listReads += 1
                return (42, following(point))
            }, frame: { id in
                frameReads += 1
                #expect(id == 42)
                return following(mouse)
            })
        }
        #expect(drag.window?.id == 42)
        #expect(drag.window?.startFrame == frame)
        // The window list once, at the threshold; its frame once more to see it follow.
        #expect(listReads == 1)
        #expect(frameReads == 1)
    }

    @Test func selectionThatLeavesTheWindowInPlaceIsIgnored() {
        var drag = SnapDrag(startMouse: start)
        var frameReads = 0
        for x in stride(from: 510, through: 700, by: 10) {
            drag.moved(to: CGPoint(x: CGFloat(x), y: 700), windowUnder: { _ in (42, frame) },
                       frame: { _ in frameReads += 1; return frame })
        }
        #expect(drag.phase == .ignored)
        // Read at 20…70 points away: undecided until past `giveUp`, then no more reads.
        #expect(frameReads == 6)
    }

    @Test func resizeIsIgnoredAtOnce() {
        var drag = SnapDrag(startMouse: start)
        let bigger = CGRect(x: frame.minX, y: frame.minY, width: frame.width + 20, height: frame.height + 20)
        drag.moved(to: CGPoint(x: 512, y: 690), windowUnder: { _ in (42, frame) }, frame: { _ in frame })
        drag.moved(to: CGPoint(x: 520, y: 680), windowUnder: { _ in (42, frame) }, frame: { _ in bigger })
        #expect(drag.phase == .ignored)
    }

    @Test func dragOverNoTrackedWindowLooksOnlyOnce() {
        var drag = SnapDrag(startMouse: start)
        var listReads = 0
        for x in stride(from: 510, through: 900, by: 30) {
            drag.moved(to: CGPoint(x: CGFloat(x), y: 700), windowUnder: { _ in listReads += 1; return nil },
                       frame: { _ in Issue.record("no window to read"); return nil })
        }
        #expect(drag.phase == .ignored)
        #expect(listReads == 1)
    }

    @Test func windowThatStopsAnsweringEndsTheDrag() {
        var drag = SnapDrag(startMouse: start)
        drag.moved(to: CGPoint(x: 512, y: 700), windowUnder: { _ in (42, frame) }, frame: { _ in frame })
        drag.moved(to: CGPoint(x: 520, y: 700), windowUnder: { _ in (42, frame) }, frame: { _ in nil })
        #expect(drag.phase == .ignored)
    }

    @Test func startFrameUndoesTheMouseTravel() {
        let mouse = CGPoint(x: 530, y: 650)
        #expect(SnapDrag.startFrame(following(mouse), at: mouse, pressedAt: start) == frame)
    }
}
