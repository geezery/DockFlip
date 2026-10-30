import AppKit
import ApplicationServices
import Testing
@testable import DockFlipKit

/// Counts the reads a stand-in app answers, from the thread each ran on.
private final class Reads: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var onMain = false

    /// Returns which read this is, counting from 1.
    func add() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        if Thread.isMainThread { onMain = true }
        return count
    }

    var total: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    var anyOnMain: Bool {
        lock.lock()
        defer { lock.unlock() }
        return onMain
    }
}

@Suite("WindowRegistry")
@MainActor
struct WindowRegistryTests {
    @Test func hasWindowsAnswersFromWhatIsTracked() {
        // The Dock click tap asks this for every press on an icon: memory only, no Accessibility.
        let registry = WindowRegistry()
        #expect(!registry.hasWindows(bundleID: "com.apple.Safari"))
        registry.windows[7] = WindowSnapshot(
            id: 7, pid: 42, bundleID: "com.apple.Safari", appName: "Safari", icon: nil,
            title: "", frame: .zero, isMinimized: true, isAppHidden: false
        )
        #expect(registry.hasWindows(bundleID: "com.apple.Safari"))
        #expect(!registry.hasWindows(bundleID: "com.apple.mail"))
    }

    @Test(.timeLimit(.minutes(1)))
    func readsAnAppsWindowsOffTheMainThread() async {
        // A hung app answers only after the 1 s timeout. Pointing at its Dock icon
        // must not hold up the main thread, which every click passes through.
        let (registry, tracked) = makeRegistry()
        let reads = Reads()
        let answer = DispatchSemaphore(value: 0)
        let window = SendableElement(element: AXUIElementCreateApplication(tracked.pid))
        tracked.readWindows = { _ in
            _ = reads.add()
            _ = answer.wait(timeout: .now() + 5)
            return WindowsRead(error: .success, windows: [
                WindowsRead.Window(id: 7, element: window.element, isStandard: true, attributes: WindowAttributes(title: "Report"))
            ])
        }
        let changes = changeStream(of: registry)
        registry.refreshWindows(of: tracked)
        // Back before the app answered.
        #expect(registry.window(7) == nil)
        answer.signal()
        for await _ in changes where registry.window(7) != nil { break }
        #expect(registry.window(7)?.title == "Report")
        #expect(reads.total == 1)
        #expect(!reads.anyOnMain)
    }

    @Test(.timeLimit(.minutes(1)))
    func requestsDuringAReadMakeOneMoreRead() async {
        // Hovering a hung app's icon again and again queues one more read, not one per hover.
        let (registry, tracked) = makeRegistry()
        let reads = Reads()
        let answer = DispatchSemaphore(value: 0)
        tracked.readWindows = { _ in
            if reads.add() == 1 { _ = answer.wait(timeout: .now() + 5) }
            return WindowsRead(error: .success, windows: [])
        }
        let changes = changeStream(of: registry)
        registry.refreshWindows(of: tracked)
        registry.refreshWindows(of: tracked)
        registry.refreshWindows(of: tracked)
        answer.signal()
        for await _ in changes where reads.total >= 2 && !tracked.isReading { break }
        #expect(reads.total == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func aHungAppKeepsItsWindowsAndIsFlagged() async {
        // A failed read is not an answer: "Not responding", and the windows stay.
        let (registry, tracked) = makeRegistry()
        tracked.windowElements[7] = AXUIElementCreateApplication(tracked.pid)
        registry.windows[7] = WindowSnapshot(
            id: 7, pid: tracked.pid, bundleID: nil, appName: "Hung", icon: nil,
            title: "Report", frame: .zero, isMinimized: false, isAppHidden: false
        )
        tracked.readWindows = { _ in WindowsRead(error: .cannotComplete, windows: []) }
        let changes = changeStream(of: registry)
        registry.refreshWindows(of: tracked)
        for await _ in changes where registry.unresponsive.contains(tracked.pid) { break }
        #expect(registry.window(7)?.title == "Report")
        #expect(tracked.windowElements[7] != nil)
    }

    /// A registry tracking this test process as its one app; its windows come
    /// from the test's own `readWindows`.
    private func makeRegistry() -> (WindowRegistry, TrackedApp) {
        let registry = WindowRegistry()
        let tracked = TrackedApp(app: .current, registry: registry)
        registry.apps[tracked.pid] = tracked
        return (registry, tracked)
    }

    private func changeStream(of registry: WindowRegistry) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        registry.addObserver { continuation.yield() }
        return stream
    }
}
