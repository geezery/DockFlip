import CoreGraphics
import Testing
@testable import DockFlipKit

@Suite("SnapEngine")
struct SnapEngineTests {
    let area = CGRect(x: 0, y: 25, width: 1440, height: 827)

    @Test func windowsKeyboardSequence() {
        // Free → left half → top-left quarter → left half → bottom-left → minimize.
        #expect(SnapEngine.action(for: .left, current: nil, display: 0, displayCount: 1) == .snap(.leftHalf, display: 0))
        #expect(SnapEngine.action(for: .up, current: .leftHalf, display: 0, displayCount: 1) == .snap(.topLeft, display: 0))
        #expect(SnapEngine.action(for: .down, current: .topLeft, display: 0, displayCount: 1) == .snap(.leftHalf, display: 0))
        #expect(SnapEngine.action(for: .down, current: .leftHalf, display: 0, displayCount: 1) == .snap(.bottomLeft, display: 0))
        #expect(SnapEngine.action(for: .down, current: .bottomLeft, display: 0, displayCount: 1) == .minimize)
    }

    @Test func maximizeAndRestore() {
        #expect(SnapEngine.action(for: .up, current: nil, display: 0, displayCount: 1) == .snap(.maximized, display: 0))
        #expect(SnapEngine.action(for: .down, current: .maximized, display: 0, displayCount: 1) == .restore)
        #expect(SnapEngine.action(for: .down, current: nil, display: 0, displayCount: 1) == .minimize)
        #expect(SnapEngine.action(for: .left, current: .rightHalf, display: 0, displayCount: 1) == .restore)
    }

    @Test func crossesToNeighbouringDisplay() {
        #expect(SnapEngine.action(for: .right, current: .rightHalf, display: 0, displayCount: 2) == .snap(.leftHalf, display: 1))
        #expect(SnapEngine.action(for: .left, current: .leftHalf, display: 1, displayCount: 2) == .snap(.rightHalf, display: 0))
        #expect(SnapEngine.action(for: .right, current: .rightHalf, display: 1, displayCount: 2) == SnapAction.none)
    }

    @Test func rectsTileTheArea() {
        let left = SnapEngine.rect(for: .leftHalf, in: area)
        let right = SnapEngine.rect(for: .rightHalf, in: area)
        #expect(left.maxX == right.minX)
        #expect(left.width + right.width == area.width)
        let topRight = SnapEngine.rect(for: .topRight, in: area)
        let bottomRight = SnapEngine.rect(for: .bottomRight, in: area)
        #expect(topRight.maxY == bottomRight.minY)
        #expect(bottomRight.maxY == area.maxY)
    }

    @Test func detectsRegionWithTolerance() {
        let snapped = SnapEngine.rect(for: .leftHalf, in: area).insetBy(dx: 3, dy: 5)
        #expect(SnapEngine.region(matching: snapped, in: area) == .leftHalf)
        #expect(SnapEngine.region(matching: CGRect(x: 200, y: 200, width: 600, height: 400), in: area) == nil)
    }

    @Test func translateKeepsWindowOnTarget() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = CGRect(x: 1000, y: 0, width: 2000, height: 1000)
        let moved = SnapEngine.translate(CGRect(x: 500, y: 400, width: 400, height: 300), from: source, to: target)
        #expect(target.contains(moved))
        #expect(moved.size == CGSize(width: 400, height: 300))
    }

    @Test func draggedOffHalfTakesBackItsSizeUnderTheMouse() {
        // Snapped left at 720 wide; grabbed a quarter across the title bar, 10 below the top.
        let snapped = SnapEngine.rect(for: .leftHalf, in: area).offsetBy(dx: 300, dy: 0)
        let mouse = CGPoint(x: snapped.minX + 180, y: snapped.minY + 10)
        let earlier = CGSize(width: 800, height: 500)
        let frame = SnapEngine.unsnappedFrame(size: earlier, from: snapped, mouse: mouse)
        #expect(frame.size == earlier)
        #expect(frame.minX == mouse.x - 200)
        #expect(frame.minY == snapped.minY)
        #expect(frame.contains(mouse))
    }

    @Test func unsnappedFrameKeepsTheMouseInsideASmallerWindow() {
        let snapped = CGRect(x: 0, y: 25, width: 720, height: 827)
        // Grabbed further down than the earlier window is tall.
        let mouse = CGPoint(x: 700, y: 625)
        let frame = SnapEngine.unsnappedFrame(size: CGSize(width: 400, height: 300), from: snapped, mouse: mouse)
        #expect(frame.maxY == mouse.y)
        #expect(frame.minX <= mouse.x && mouse.x <= frame.maxX)
    }
}
