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
    /// Windows whose state is being read on the app's queue after a notification.
    var updating = Set<CGWindowID>()
    /// Windows that changed again during that read: read once more after it.
    var updateAgain = Set<CGWindowID>()
    /// Reads one window's state on its queue; tests stand in their own.
    var readWindow: @Sendable (CGWindowID, SendableElement) -> WindowsRead.Window = {
        WindowsRead.Window.read(id: $0, element: $1.element).window
    }
    /// Reads the app's windows on its queue; tests stand in an app of their own.
    var readWindows: @Sendable (AXUIElement) -> WindowsRead = { WindowsRead.read(app: $0) }
    /// Asks the app for its focused window on its queue; tests stand in their own.
    var readFocusedWindow: @Sendable (AXUIElement) -> SendableElement? = {
        $0.element(kAXFocusedWindowAttribute).map { SendableElement(element: $0) }
    }
    /// Reads the state of the windows already known on its queue; tests stand in their own.
    var readKnownWindows: @Sendable ([CGWindowID: SendableElement]) -> [WindowsRead.Window] = {
        WindowsRead.read(known: $0)
    }

    var pid: pid_t { app.processIdentifier }

    init(app: NSRunningApplication, registry: WindowRegistry) {
        self.app = app
        self.element = AXUIElementCreateApplication(app.processIdentifier)
        self.registry = registry
    }

    func id(of element: AXUIElement) -> CGWindowID? {
        // It runs in the Accessibility callback on the main thread: the elements
        // known are compared first, in memory, before the window id is asked for.
        if let id = windowElements.first(where: { CFEqual($0.value, element) })?.key { return id }
        // Often a window that is already gone (its destroyed notification): kept
        // out of the self-check, where its failed lookup would read as macOS's.
        if let id = element.windowIDOfAnyElement, windowElements[id] != nil { return id }
        return nil
    }
}
