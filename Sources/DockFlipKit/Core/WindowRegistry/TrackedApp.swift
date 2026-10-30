import AppKit
import ApplicationServices

/// Per-application Accessibility state.
@MainActor
final class TrackedApp {
    let app: NSRunningApplication
    let element: AXUIElement
    var observer: AXObserver?
    var windowElements: [CGWindowID: AXUIElement] = [:]
    weak var registry: WindowRegistry?
    /// A re-read is scheduled because the app did not answer in time.
    var retryPending = false
    var retryCount = 0
    /// A read of its windows is on the app's queue.
    var isReading = false
    /// Something changed while it was reading: read once more after it.
    var readAgain = false
    /// Once its windows are read, put its focused window first in the MRU order
    /// if it is the active app: a new window is known only after the read.
    var bringFocusedForward = false
    /// Reads the app's windows on its queue; tests stand in an app of their own.
    var readWindows: @Sendable (AXUIElement) -> WindowsRead = { WindowsRead.read(app: $0) }

    var pid: pid_t { app.processIdentifier }

    init(app: NSRunningApplication, registry: WindowRegistry) {
        self.app = app
        self.element = AXUIElementCreateApplication(app.processIdentifier)
        self.registry = registry
    }

    func id(of element: AXUIElement) -> CGWindowID? {
        // Often a window that is already gone (its destroyed notification): kept
        // out of the self-check, where its failed lookup would read as macOS's.
        if let id = element.windowIDOfAnyElement, windowElements[id] != nil { return id }
        return windowElements.first { CFEqual($0.value, element) }?.key
    }
}
