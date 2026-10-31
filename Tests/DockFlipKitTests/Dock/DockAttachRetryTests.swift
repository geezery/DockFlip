import Testing
@testable import DockFlipKit

/// A failed Dock attach is tried again a few times with one-shot waits, not
/// given up for the session and not retried forever. `FakeDock` stands in for
/// the attach and the waits, which pass at once.
@Suite("Dock: trying a failed attach again")
@MainActor
struct DockAttachRetryTests {
    @MainActor
    final class FakeDock {
        /// What each attach answers; the last answer sticks.
        var answers: [Bool]
        var tries = 0
        var slept: [Duration] = []

        init(_ answers: [Bool]) { self.answers = answers }

        func attach() -> Bool {
            defer { tries += 1 }
            return answers[min(tries, answers.count - 1)]
        }
    }

    private func makeRetry(_ dock: FakeDock) -> DockAttachRetry {
        DockAttachRetry(sleep: { dock.slept.append($0) })
    }

    @Test func delaysAreOneTwoAndFourSeconds() {
        #expect(DockAttachRetry.delays == [.seconds(1), .seconds(2), .seconds(4)])
    }

    @Test func attachThatWorksAtOnceWaitsForNothing() {
        let dock = FakeDock([true])

        let series = makeRetry(dock).start { dock.attach() }

        #expect(series == nil)
        #expect(dock.tries == 1)
        #expect(dock.slept.isEmpty)
    }

    @Test func treeReadyOnTheSecondRetryStopsThere() async {
        let dock = FakeDock([false, false, true])

        await makeRetry(dock).start { dock.attach() }?.value

        #expect(dock.tries == 3)
        #expect(dock.slept == Array(DockAttachRetry.delays.prefix(2)))
    }

    @Test func dockThatNeverAttachesEndsAfterTheLastTry() async {
        let dock = FakeDock([false])

        await makeRetry(dock).start { dock.attach() }?.value

        #expect(dock.tries == 1 + DockAttachRetry.delays.count)
        #expect(dock.slept == DockAttachRetry.delays)
    }

    @Test func newerStartDropsTheWaitingSeries() async {
        let first = FakeDock([false])
        let second = FakeDock([false, true])
        let retry = makeRetry(first)

        let old = retry.start { first.attach() }
        let new = retry.start { second.attach() }
        await old?.value
        await new?.value

        // The first series was dropped before its first retry.
        #expect(first.tries == 1)
        #expect(second.tries == 2)
    }

    @Test func stoppedSeriesTriesNoMore() async {
        let dock = FakeDock([false])
        let retry = makeRetry(dock)

        let series = retry.start { dock.attach() }
        retry.stop()
        await series?.value

        #expect(dock.tries == 1)
    }
}
