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

    @Test(.timeLimit(.minutes(1)))
    func activationAsksForTheFocusedWindowOffTheMainThread() async {
        // macOS activates a hung app without its help: ⌘Tab to it must not hold up clicks.
        let (registry, tracked) = makeRegistry()
        let front = AXUIElementCreateApplication(101)
        let focused = AXUIElementCreateApplication(102)
        addWindow(7, element: front, to: registry, tracked)
        addWindow(8, element: focused, to: registry, tracked)
        let reads = Reads()
        let answer = DispatchSemaphore(value: 0)
        let reply = SendableElement(element: focused)
        tracked.readFocusedWindow = { _ in
            _ = reads.add()
            _ = answer.wait(timeout: .now() + 5)
            return reply
        }
        registry.activePID = tracked.pid
        registry.bringFocusedWindowToFrontLater(of: tracked)
        // Back before the app answered.
        #expect(registry.mru.items.first == 7)
        answer.signal()
        await answered(registry, tracked)
        #expect(registry.mru.items.first == 8)
        #expect(reads.total == 1)
        #expect(!reads.anyOnMain)
    }

    @Test(.timeLimit(.minutes(1)))
    func aLateFocusedWindowStaysBehindANewerActiveApp() async {
        // Activating a hung app, then another: the hung one's late answer changes nothing.
        let (registry, tracked) = makeRegistry()
        addWindow(7, element: AXUIElementCreateApplication(101), to: registry, tracked)
        let focused = AXUIElementCreateApplication(102)
        addWindow(8, element: focused, to: registry, tracked)
        let answer = DispatchSemaphore(value: 0)
        let reply = SendableElement(element: focused)
        tracked.readFocusedWindow = { _ in
            _ = answer.wait(timeout: .now() + 5)
            return reply
        }
        registry.activePID = tracked.pid
        registry.bringFocusedWindowToFrontLater(of: tracked)
        registry.activePID = tracked.pid + 1
        answer.signal()
        await answered(registry, tracked)
        #expect(registry.mru.items.first == 7)
    }

    @Test(.timeLimit(.minutes(1)))
    func hidingAnAppReadsItsWindowsOffTheMainThread() async {
        // ⌘H or Show Desktop on a hung app must not hold up clicks for 1 s per window.
        let (registry, tracked) = makeRegistry()
        addWindow(7, element: AXUIElementCreateApplication(101), to: registry, tracked, title: "Old", isAppHidden: true)
        let reads = Reads()
        let answer = DispatchSemaphore(value: 0)
        tracked.readKnownWindows = { known in
            _ = reads.add()
            _ = answer.wait(timeout: .now() + 5)
            return known.map { WindowsRead.Window(id: $0.key, element: $0.value.element, isStandard: true, attributes: WindowAttributes(title: "New")) }
        }
        registry.appHiddenOrShown(tracked)
        // Whether the app is hidden is known at once, without asking the app.
        #expect(registry.window(7)?.isAppHidden == tracked.app.isHidden)
        #expect(registry.window(7)?.title == "Old")
        answer.signal()
        await answered(registry, tracked)
        #expect(registry.window(7)?.title == "New")
        #expect(reads.total == 1)
        #expect(!reads.anyOnMain)
    }

    @Test(.timeLimit(.minutes(1)))
    func aWindowClosedDuringTheHideReadStaysGone() async {
        let (registry, tracked) = makeRegistry()
        addWindow(7, element: AXUIElementCreateApplication(101), to: registry, tracked)
        let answer = DispatchSemaphore(value: 0)
        tracked.readKnownWindows = { known in
            _ = answer.wait(timeout: .now() + 5)
            return known.map { WindowsRead.Window(id: $0.key, element: $0.value.element, isStandard: true, attributes: WindowAttributes(title: "New")) }
        }
        registry.appHiddenOrShown(tracked)
        tracked.windowElements[7] = nil
        registry.windows[7] = nil
        answer.signal()
        await answered(registry, tracked)
        #expect(registry.window(7) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func aMovedWindowIsReadOffTheMainThread() async {
        // An app that hangs while its window is dragged must not hold up clicks.
        let (registry, tracked) = makeRegistry()
        addWindow(7, element: AXUIElementCreateApplication(101), to: registry, tracked, title: "Old")
        let reads = Reads()
        let answer = DispatchSemaphore(value: 0)
        tracked.readWindow = { id, element in
            _ = reads.add()
            _ = answer.wait(timeout: .now() + 5)
            return WindowsRead.Window(id: id, element: element.element, isStandard: true, attributes: WindowAttributes(title: "New"))
        }
        registry.windowChanged(7, of: tracked)
        // Back before the app answered.
        #expect(registry.window(7)?.title == "Old")
        answer.signal()
        await answered(registry, tracked)
        #expect(registry.window(7)?.title == "New")
        #expect(reads.total == 1)
        #expect(!reads.anyOnMain)
    }

    @Test(.timeLimit(.minutes(1)))
    func aDragMakesOneMoreReadNotOneEach() async {
        // Hundreds of moves during a read on its way queue one more read, which
        // carries where the window ended up.
        let (registry, tracked) = makeRegistry()
        addWindow(7, element: AXUIElementCreateApplication(101), to: registry, tracked)
        let reads = Reads()
        let answer = DispatchSemaphore(value: 0)
        tracked.readWindow = { id, element in
            let count = reads.add()
            if count == 1 { _ = answer.wait(timeout: .now() + 5) }
            let frame = CGRect(x: count * 100, y: 0, width: 400, height: 300)
            return WindowsRead.Window(id: id, element: element.element, isStandard: true, attributes: WindowAttributes(frame: frame))
        }
        let changes = changeStream(of: registry)
        for _ in 0..<50 { registry.windowChanged(7, of: tracked) }
        answer.signal()
        for await _ in changes where reads.total >= 2 && tracked.updating.isEmpty { break }
        let frame = registry.window(7)?.frame
        #expect(reads.total == 2)
        #expect(frame?.minX == 200)
        #expect(tracked.updateAgain.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func aWindowClosedDuringItsMoveReadStaysGone() async {
        let (registry, tracked) = makeRegistry()
        addWindow(7, element: AXUIElementCreateApplication(101), to: registry, tracked)
        let answer = DispatchSemaphore(value: 0)
        tracked.readWindow = { id, element in
            _ = answer.wait(timeout: .now() + 5)
            return WindowsRead.Window(id: id, element: element.element, isStandard: true, attributes: WindowAttributes(title: "New"))
        }
        registry.windowChanged(7, of: tracked)
        tracked.windowElements[7] = nil
        registry.windows[7] = nil
        answer.signal()
        await answered(registry, tracked)
        #expect(registry.window(7) == nil)
        #expect(tracked.updating.isEmpty)
    }

    /// Waits until the calls asked of the app so far have answered on the main actor:
    /// its queue runs them in order, and their answers come back in that order.
    private func answered(_ registry: WindowRegistry, _ tracked: TrackedApp) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            registry.appQueues.run(for: tracked.pid, {}, then: { _ in done.resume() })
        }
    }

    private func addWindow(
        _ id: CGWindowID, element: AXUIElement, to registry: WindowRegistry, _ tracked: TrackedApp,
        title: String = "", isAppHidden: Bool = false
    ) {
        tracked.windowElements[id] = element
        registry.windows[id] = WindowSnapshot(
            id: id, pid: tracked.pid, bundleID: nil, appName: "App", icon: nil,
            title: title, frame: .zero, isMinimized: false, isAppHidden: isAppHidden
        )
        registry.mru.appendIfMissing(id)
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
