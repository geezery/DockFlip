import Testing
@testable import DockFlipKit

@Suite("EdgeTilingHint")
struct EdgeTilingHintTests {
    /// Plays drags against one `EdgeTilingHint`, counting reads of the tiling switch.
    private struct Launch {
        var hint = EdgeTilingHint()
        var reads = 0

        /// One drag over `zones` snap zones: what each zone's preview showed.
        mutating func drag(zones: Int = 3, tilingOn: Bool) -> [Bool] {
            hint.newDrag()
            var shown: [Bool] = []
            // A local count: the closure may not capture `self` while `hint` changes.
            var read = 0
            for _ in 0..<zones {
                shown.append(hint.showsHint(tilingOn: { read += 1; return tilingOn }))
            }
            reads += read
            return shown
        }
    }

    @Test func firstDragWithTilingOnShowsItForTheWholeDrag() {
        var launch = Launch()
        let first = launch.drag(tilingOn: true)
        #expect(first == [true, true, true])
        #expect(launch.hint.shown)
        #expect(launch.reads == 1)
    }

    @Test func onlyOncePerLaunch() {
        var launch = Launch()
        _ = launch.drag(tilingOn: true)
        let second = launch.drag(tilingOn: true)
        let third = launch.drag(tilingOn: true)
        #expect(second == [false, false, false])
        #expect(third == [false, false, false])
        // Shown once: macOS's preferences are not read again.
        #expect(launch.reads == 1)
    }

    @Test func neverWithTilingOff() {
        var launch = Launch()
        var shown: [Bool] = []
        for _ in 0..<3 {
            shown += launch.drag(tilingOn: false)
        }
        #expect(!shown.contains(true))
        #expect(!launch.hint.shown)
        // Once per drag, not once per snap zone.
        #expect(launch.reads == 3)
    }

    @Test func tilingSwitchedOnLaterShowsItThen() {
        var launch = Launch()
        _ = launch.drag(tilingOn: false)
        let later = launch.drag(tilingOn: true)
        #expect(later == [true, true, true])
    }

    @Test func aDragThatNeverReachesAZoneReadsNothing() {
        var launch = Launch()
        let shown = launch.drag(zones: 0, tilingOn: true)
        #expect(shown.isEmpty)
        #expect(launch.reads == 0)
        #expect(!launch.hint.shown)
    }
}
