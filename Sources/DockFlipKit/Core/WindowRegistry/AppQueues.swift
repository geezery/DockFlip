import Foundation

/// One serial queue per app for the Accessibility calls that wait on the app.
///
/// A hung app answers each call only after the messaging timeout (1 s). On the
/// main thread that wait would hold up its run loop, and with it the event taps
/// on it, which every click and key press on the Mac passes through. Here it
/// holds up only that app's queue: its calls still run in the order asked, and
/// a hung app never delays another app's.
@MainActor
final class AppQueues {
    private var queues: [pid_t: DispatchQueue] = [:]

    /// Runs `work` on the app's queue after the calls asked before it, then
    /// `done` with its result on the main actor.
    func run<T: Sendable>(
        for pid: pid_t,
        _ work: @escaping @Sendable () -> T,
        then done: (@MainActor @Sendable (T) -> Void)? = nil
    ) {
        let queue = queues[pid] ?? DispatchQueue(label: "DockFlip.app.\(pid)", qos: .userInitiated)
        queues[pid] = queue
        queue.async {
            let result = work()
            guard let done else { return }
            Task { @MainActor in done(result) }
        }
    }

    /// The app quit. Calls still queued for it finish on their own.
    func forget(_ pid: pid_t) {
        queues[pid] = nil
    }
}
