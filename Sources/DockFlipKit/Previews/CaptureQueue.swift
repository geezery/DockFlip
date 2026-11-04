/// Which captures run now. Pure, unit-tested.
///
/// ScreenCaptureKit drops or stalls captures when many start at once (⌘Tab used
/// to ask for 16 side by side), so at most `limit` run together and the rest wait
/// their turn, first asked first. A capture for what the user is looking at right
/// now (the hovered window, the card ⌘Tab just stepped to) jumps the line.
struct CaptureQueue<ID: Hashable> {
    let limit: Int
    private(set) var running = Set<ID>()
    /// Next to start first.
    private(set) var waiting: [ID] = []

    init(limit: Int = 3) {
        self.limit = max(1, limit)
    }

    /// Asks to capture `id`, once per capture. True when it may start now;
    /// otherwise it waits until `finish` hands it out.
    mutating func request(_ id: ID, urgent: Bool) -> Bool {
        if running.contains(id) || waiting.contains(id) { return false }
        if running.count < limit {
            running.insert(id)
            return true
        }
        if urgent { waiting.insert(id, at: 0) } else { waiting.append(id) }
        return false
    }

    /// Moves a waiting `id` to the front of the line; nothing for one running or not asked for.
    mutating func promote(_ id: ID) {
        guard let index = waiting.firstIndex(of: id) else { return }
        waiting.remove(at: index)
        waiting.insert(id, at: 0)
    }

    /// `id` finished. Returns the captures that may start now.
    mutating func finish(_ id: ID) -> [ID] {
        running.remove(id)
        var started: [ID] = []
        while running.count < limit, !waiting.isEmpty {
            let next = waiting.removeFirst()
            running.insert(next)
            started.append(next)
        }
        return started
    }
}
