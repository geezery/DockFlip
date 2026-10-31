import ApplicationServices

/// Subscribes a newly tracked app to its Accessibility observer.
///
/// `AXObserverAddNotification` waits on the app for its answer, as any
/// Accessibility call does: an app that is busy at launch costs the messaging
/// timeout (1 s) per call, three calls per app. So it runs on the app's queue
/// (`AppQueues`), like `WindowSubscriber`; the observer's run loop source is
/// added on the main run loop once the app answered.
struct AppSubscriber: @unchecked Sendable {
    /// The notifications each app is subscribed to.
    static let notifications: [String] = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification
    ]

    let observer: AXObserver
    /// The `TrackedApp`, unretained, as the callback expects it.
    let refcon: UnsafeMutableRawPointer

    /// Waits on the app; call it on the app's queue, never on the main thread.
    /// Returns each registration's `AXError` raw value, in `notifications` order.
    func subscribe(_ app: SendableElement) -> [Int32] {
        Self.notifications.map { name in
            AXObserverAddNotification(observer, app.element, name as CFString, refcon).rawValue
        }
    }
}
