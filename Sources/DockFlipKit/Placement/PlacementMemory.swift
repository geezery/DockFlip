import AppKit

/// Windows 11's "Remember window locations based on monitor connection":
/// remembers where every window was for each set of displays, and puts the
/// windows back when that set of displays is connected again.
@MainActor
final class PlacementMemory {
    private let registry: WindowRegistry
    /// Display-set signature → window id → frame (AX space).
    private var layouts: [String: [CGWindowID: CGRect]] = [:]
    private var layoutOrder: [String] = []
    private var currentSignature = ""
    /// Saving pauses while macOS shuffles windows after a display change.
    private var pausedUntil = Date.distantPast
    private var saveTask: Task<Void, Never>?
    private var tokens: [NSObjectProtocol] = []

    private static let maxLayouts = 8

    init(registry: WindowRegistry) {
        self.registry = registry
    }

    func start() {
        currentSignature = Self.signature()
        registry.addObserver { [weak self] in self?.scheduleSave() }
        tokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged() }
        })
        saveNow()
    }

    // MARK: - Display changes

    private func displaysChanged() {
        let signature = Self.signature()
        guard signature != currentSignature else { return }
        let screenCount = NSScreen.screens.count
        Log.app.notice("Displays changed: \(screenCount, privacy: .public) screen(s)")
        currentSignature = signature
        pausedUntil = Date().addingTimeInterval(4)
        saveTask?.cancel()
        saveTask = nil

        guard let layout = layouts[signature] else { return }
        // Give macOS a moment to finish moving windows itself, then put them back.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, self.currentSignature == signature else { return }
            self.restore(layout)
        }
    }

    private func restore(_ layout: [CGWindowID: CGRect]) {
        let start = Perf.now()
        let screens = NSScreen.screens.map { DisplayLayout.axFrame(of: $0) }
        var moved = 0
        for (id, frame) in layout {
            guard let window = registry.window(id), !window.isMinimized,
                  screens.contains(where: { $0.intersects(frame) }),
                  let current = registry.liveFrame(of: id),
                  current.integral != frame.integral else { continue }
            registry.setFrame(of: id, to: frame)
            moved += 1
        }
        Perf.shared.record("placement.restore", since: start, detail: "\(moved) windows")
        Log.app.notice("Restored \(moved, privacy: .public) window positions")
    }

    // MARK: - Saving

    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            self.saveNow()
        }
    }

    private func saveNow() {
        guard Date() >= pausedUntil else {
            scheduleSave()
            return
        }
        // Only save for the display set that is really connected now.
        let signature = Self.signature()
        guard signature == currentSignature else { return }

        let screens = NSScreen.screens.map { DisplayLayout.axFrame(of: $0) }
        var layout = layouts[signature] ?? [:]
        for window in registry.currentSpaceWindows() where !window.isMinimized && !window.isAppHidden {
            guard screens.contains(where: { $0.intersects(window.frame) }),
                  !screens.contains(where: { $0 == window.frame }) else { continue } // skip full-screen
            layout[window.id] = window.frame
        }
        // Forget windows that are gone.
        let alive = Set(WindowServer.windows(onScreenOnly: false).map(\.id))
        layout = layout.filter { alive.contains($0.key) }

        layouts[signature] = layout
        layoutOrder.removeAll { $0 == signature }
        layoutOrder.append(signature)
        while layoutOrder.count > Self.maxLayouts {
            layouts[layoutOrder.removeFirst()] = nil
        }
    }

    /// Identifies the connected set of displays and how they are arranged.
    static func signature() -> String {
        NSScreen.screens.map { screen -> String in
            let id = DisplayLayout.displayID(of: screen)
            var name = "\(id)"
            if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
                name = CFUUIDCreateString(nil, uuid) as String
            }
            let f = screen.frame
            return "\(name)@\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width))x\(Int(f.height))"
        }
        .sorted()
        .joined(separator: "|")
    }
}
