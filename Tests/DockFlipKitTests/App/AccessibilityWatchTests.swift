import Testing
@testable import DockFlipKit

/// Setup's permission step turns green by events, not a repeating timer. `FakeMac`
/// stands in for `AXIsProcessTrusted()` and for the waits, which pass at once.
@Suite("Setup: noticing the Accessibility switch")
@MainActor
struct AccessibilityWatchTests {
    @MainActor
    final class FakeMac {
        /// What each call of `AXIsProcessTrusted()` answers; the last answer sticks.
        var answers: [Bool]
        var asked = 0
        var slept: [Duration] = []

        init(_ answers: [Bool]) { self.answers = answers }

        func isTrusted() -> Bool {
            defer { asked += 1 }
            return answers[min(asked, answers.count - 1)]
        }
    }

    private func makeWatch(_ mac: FakeMac) -> (AccessibilityWatch, Recorder) {
        let watch = AccessibilityWatch(isTrusted: { mac.isTrusted() }, sleep: { mac.slept.append($0) })
        let changes = Recorder()
        watch.onChange = { changes.values.append($0) }
        return (watch, changes)
    }

    @MainActor
    final class Recorder {
        var values: [Bool] = []
    }

    @Test func switchTurnedOnIsNoticedAndTheLooksStop() async {
        // The first look after the announcement still gets the old answer.
        let mac = FakeMac([false, false, true])
        let (watch, changes) = makeWatch(mac)

        await watch.settingsChanged().value

        #expect(watch.granted)
        #expect(changes.values == [true])
        #expect(mac.slept == Array(AccessibilityWatch.rechecks.prefix(2)))
    }

    @Test func announcementForAnotherAppEndsAfterTheLastLook() async {
        let mac = FakeMac([false])
        let (watch, changes) = makeWatch(mac)

        await watch.settingsChanged().value

        #expect(!watch.granted)
        #expect(changes.values.isEmpty)
        #expect(mac.slept == AccessibilityWatch.rechecks)
    }

    @Test func looksAreFewAndTheFirstIsWithinASecond() {
        let rechecks = AccessibilityWatch.rechecks
        #expect(!rechecks.isEmpty && rechecks.count <= 5)
        #expect(rechecks[0] < .seconds(1))
        #expect(rechecks == rechecks.sorted())
    }

    @Test func checkReportsOnlyChanges() {
        let mac = FakeMac([false, false, true, true, false])
        let (watch, changes) = makeWatch(mac)

        watch.check()
        watch.check()
        watch.check()
        watch.check()

        #expect(changes.values == [true, false])
    }

    @Test func stoppedSeriesLooksNoMore() async {
        let mac = FakeMac([false, true])
        let (watch, changes) = makeWatch(mac)

        let series = watch.settingsChanged()
        watch.stop()
        await series.value

        #expect(changes.values.isEmpty)
        #expect(!watch.granted)
    }
}
