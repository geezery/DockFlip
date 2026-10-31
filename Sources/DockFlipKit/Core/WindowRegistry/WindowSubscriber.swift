import ApplicationServices

/// Subscribes a newly seen window to the app's Accessibility observer.
///
/// `AXObserverAddNotification` registers with the app itself and waits for its
/// answer: an app that listed its windows and then stalls costs the messaging
/// timeout (1 s) per call, six calls per window. So it runs on the app's queue
/// (`AppQueues`); the observer's run loop source stays on the main run loop,
/// where the callbacks arrive as before.
struct WindowSubscriber: @unchecked Sendable {
    /// The notifications each window is subscribed to.
    static let notifications: [String] = [
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXTitleChangedNotification,
        kAXMovedNotification,
        kAXResizedNotification
    ]

    let observer: AXObserver
    /// The `TrackedApp`, unretained, as the callback expects it. The callback
    /// never sees it after the app is untracked: its run loop source is removed then.
    let refcon: UnsafeMutableRawPointer

    /// Waits on the app; call it on the app's queue, never on the main thread.
    func subscribe(_ window: SendableElement) {
        for name in Self.notifications {
            _ = AXObserverAddNotification(observer, window.element, name as CFString, refcon)
        }
    }
}
