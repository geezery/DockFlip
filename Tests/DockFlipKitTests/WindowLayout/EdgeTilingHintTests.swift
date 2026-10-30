import Testing
@testable import DockFlipKit

@Suite("EdgeTilingHint")
struct EdgeTilingHintTests {
    /// One drag that passes over `zones` snap zones; what each zone's preview showed.
    private func drag(_ hint: inout EdgeTilingHint, zones: Int = 3, tilingOn: Bool, reads: inout Int) -> [Bool] {
        hint.newDrag()
        return (0..<zones).map { _ in
            hint.showsHint(tilingOn: { reads += 1; return tilingOn })
        }
    }

    @Test func firstDragWithTilingOnShowsItForTheWholeDrag() {
        var hint = EdgeTilingHint()
        var reads = 0
        #expect(drag(&hint, tilingOn: true, reads: &reads) == [true, true, true])
        #expect(hint.shown)
        #expect(reads == 1)
    }

    @Test func onlyOncePerLaunch() {
        var hint = EdgeTilingHint()
        var reads = 0
        _ = drag(&hint, tilingOn: true, reads: &reads)
        #expect(drag(&hint, tilingOn: true, reads: &reads) == [false, false, false])
        #expect(drag(&hint, tilingOn: true, reads: &reads) == [false, false, false])
        // Shown once: macOS's preferences are not read again.
        #expect(reads == 1)
    }

    @Test func neverWithTilingOff() {
        var hint = EdgeTilingHint()
        var reads = 0
        for _ in 0..<3 {
            #expect(drag(&hint, tilingOn: false, reads: &reads) == [false, false, false])
        }
        #expect(!hint.shown)
        // Once per drag, not once per snap zone.
        #expect(reads == 3)
    }

    @Test func tilingSwitchedOnLaterShowsItThen() {
        var hint = EdgeTilingHint()
        var reads = 0
        _ = drag(&hint, tilingOn: false, reads: &reads)
        #expect(drag(&hint, tilingOn: true, reads: &reads) == [true, true, true])
    }

    @Test func aDragThatNeverReachesAZoneReadsNothing() {
        var hint = EdgeTilingHint()
        var reads = 0
        #expect(drag(&hint, zones: 0, tilingOn: true, reads: &reads) == [])
        #expect(reads == 0)
        #expect(!hint.shown)
    }
}
