import Foundation
import Testing
@testable import DockFlipKit

/// Calls made on the queues, in the order they ran (they run off the main thread).
private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []

    func add(_ call: String) {
        lock.lock()
        calls.append(call)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

@Suite("AppQueues")
@MainActor
struct AppQueuesTests {
    @Test func oneAppsCallsRunInTheOrderAsked() async {
        // Unminimize, raise, then minimize again must not overtake each other.
        let queues = AppQueues()
        let log = CallLog()
        let (finished, finish) = AsyncStream<Void>.makeStream()
        queues.run(for: 1, {
            Thread.sleep(forTimeInterval: 0.05)
            log.add("first")
        })
        queues.run(for: 1, { log.add("second") }, then: { _ in finish.yield() })
        for await _ in finished { break }
        #expect(log.all == ["first", "second"])
    }

    @Test func aHungAppDoesNotHoldUpAnotherApp() async {
        // App 1 answers only after the messaging timeout; app 2's call runs meanwhile.
        let queues = AppQueues()
        let log = CallLog()
        let hung = DispatchSemaphore(value: 0)
        let (finished, finish) = AsyncStream<[String]>.makeStream()
        queues.run(for: 1, {
            _ = hung.wait(timeout: .now() + 10)
            log.add("hung app")
        })
        // The log is read as app 2's call runs, not after the hop back to a main actor
        // that other suites keep busy: on CI that hop once took longer than the hang.
        queues.run(for: 2, { () -> [String] in
            log.add("other app")
            return log.all
        }, then: { seen in finish.yield(seen) })
        var seen: [String] = []
        for await calls in finished {
            seen = calls
            break
        }
        hung.signal()
        #expect(seen == ["other app"])
    }

    @Test func theAnswerComesBackOnTheMainActor() async {
        let queues = AppQueues()
        let (answers, answer) = AsyncStream<Bool>.makeStream()
        queues.run(for: 1, { Thread.isMainThread }, then: { ranOnMain in
            answer.yield(!ranOnMain && Thread.isMainThread)
        })
        var offMainThenOnMain = false
        for await value in answers {
            offMainThenOnMain = value
            break
        }
        #expect(offMainThenOnMain)
    }
}
