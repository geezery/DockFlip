import AppKit
import SwiftUI

/// Drives the ⌘Tab switcher. While it is open, its full-screen panel is the key
/// window and has the keyboard, so the app you came from (say, Terminal) gets no
/// key presses. Releasing ⌘ opens the window in front; Esc or a click outside goes
/// back to where you were. The panel takes the keyboard at once but is drawn
/// only once ⌘ has been held a moment (`SwitcherReveal`), so quick hops never flash.
/// How the panel takes the keyboard without activating DockFlip: `SwitcherPanel`.
///
/// The windows, focusing, the live ⌘ state and the panel come in from outside,
/// so tests run the whole open/step/release flow with fakes, without
/// Accessibility or a panel (`SwitcherControllerTests`).
@MainActor
final class SwitcherController {
    private let switcherWindows: @MainActor () -> [WindowSnapshot]
    private let focusWindow: @MainActor (CGWindowID) -> Void
    /// Whether ⌘ is down right now, read from the system, not from events.
    private let isCommandHeld: @MainActor () -> Bool
    /// The hold before the switcher is drawn; tests pass one that ends at once.
    private let sleep: @MainActor (Duration) async -> Void
    private let presenter: any SwitcherPresenter
    private let model: SwitcherModel
    private var selection: SwitcherSelection?
    /// Every window of this session; `model.items` holds the ones matching the filter.
    private var allWindows: [WindowSnapshot] = []
    private var allItems: [SwitcherItem] = []
    /// Typed filter. Not empty means "search mode": releasing ⌘ no longer
    /// switches, Return does. Cleared whenever the switcher closes.
    private var query = ""
    /// ⌘ is down: set when the switcher opens with ⌘ held, and again when ⌘ is
    /// pressed while it is open. Only the release that follows switches: every
    /// later modifier change without ⌘ (⇧ for ⇧Tab, ⌃, ⌥) also arrives as
    /// `.commandReleased`, and once the filter is cleared it must not switch.
    /// While ⌘ is up, only Return, a click or holding ⌘ again and letting go opens a window.
    private var commandDown = false
    private var previewTasks: [Task<Void, Never>] = []
    /// Windows whose pictures this session asked for already, so a step asks only for new ones.
    private var askedPreviews = Set<CGWindowID>()
    /// Draws the switcher once ⌘ has been held long enough (`SwitcherReveal`).
    /// Readable so tests can wait for it.
    private(set) var revealTask: Task<Void, Never>?
    /// The switcher can be seen. Until then its panel is key but invisible.
    private var isDrawn = false
    /// Whether `presenter.show()` ran this session: a quick ⌘Tab with ⌘ already up
    /// switches without it, so there is no panel to hide and no active change to undo.
    private var isShown = false

    /// Called with true when the switcher opens and false when it closes.
    var onActiveChanged: ((Bool) -> Void)?

    var isActive: Bool { selection != nil }

    convenience init(registry: WindowRegistry) {
        self.init(
            switcherWindows: { registry.switcherWindows() },
            focusWindow: { registry.focus($0) },
            isCommandHeld: { NSEvent.modifierFlags.contains(.command) },
            sleep: { try? await Task.sleep(for: $0) },
            presenter: nil
        )
    }

    /// Tests pass fakes; `presenter` nil means the real panel.
    init(
        switcherWindows: @escaping @MainActor () -> [WindowSnapshot],
        focusWindow: @escaping @MainActor (CGWindowID) -> Void,
        isCommandHeld: @escaping @MainActor () -> Bool,
        sleep: @escaping @MainActor (Duration) async -> Void,
        presenter: (any SwitcherPresenter)?
    ) {
        let model = SwitcherModel()
        self.switcherWindows = switcherWindows
        self.focusWindow = focusWindow
        self.isCommandHeld = isCommandHeld
        self.sleep = sleep
        self.model = model
        self.presenter = presenter ?? SwitcherPanel(model: model)
        model.onPick = { [weak self] index in self?.commit(at: index) }
        model.onCancel = { [weak self] in self?.cancel() }
        self.presenter.onInput = { [weak self] input in _ = self?.handle(input) }
    }

    /// Returns true when the input was consumed.
    @discardableResult
    func handle(_ input: SwitcherInput) -> Bool {
        switch input {
        case .commandTab(let shift):
            if isActive {
                step(shift ? -1 : 1)
                return true
            }
            return begin(reverse: shift)
        case .next:
            guard isActive else { return false }
            step(1)
            return true
        case .previous:
            guard isActive else { return false }
            step(-1)
            return true
        case .enter:
            guard let selection else { return false }
            commit(at: selection.index)
            return true
        case .escape:
            guard isActive else { return false }
            if query.isEmpty {
                cancel()
            } else {
                setQuery("")
            }
            return true
        case .commandReleased:
            guard commandDown else { return false }
            commandDown = false
            if let index = SwitcherRelease.windowToOpen(selection: selection, query: query, commandHeld: false) {
                commit(at: index)
            }
            return false
        case .commandPressed:
            // ⌘ held again, say after letting go of it to filter: its release
            // switches once more, unless something is typed by then. The panel's
            // monitor and the flags tap both send it, so a copy can come in after
            // ⌘ is already up again: only the live state re-arms.
            if isActive, isCommandHeld() { commandDown = true }
            return false
        case .text(let text):
            guard isActive else { return false }
            setQuery(query + text)
            return true
        case .deleteBackward:
            guard isActive else { return false }
            if !query.isEmpty { setQuery(String(query.dropLast())) }
            return true
        }
    }

    // MARK: - Lifecycle

    private func begin(reverse: Bool) -> Bool {
        Perf.shared.measure("switcher.open") { beginUnmeasured(reverse: reverse) }
    }

    private func beginUnmeasured(reverse: Bool) -> Bool {
        let windows = switcherWindows()
        guard !windows.isEmpty else { return false }

        allWindows = windows
        let previews = PreviewProvider.shared.isAvailable
        query = ""
        model.query = ""
        model.thumbnails = [:]
        model.items = windows.map { window in
            let placement = WindowAppearance.placement(of: window.frame)
            return SwitcherItem(
                windowID: window.id,
                title: window.title.isEmpty ? window.appName : window.title,
                appName: window.appName,
                icon: window.icon,
                minimap: placement?.minimap,
                isMinimized: window.isMinimized,
                isOnOtherSpace: window.isOnOtherSpace,
                document: window.document,
                screenName: placement?.screen.localizedName,
                sizeText: "\(Int(window.frame.width)) × \(Int(window.frame.height))",
                windowSize: window.frame.size,
                tint: WindowAppearance.tint(of: window),
                neverPictured: previews && PreviewProvider.neverPictured(window.bundleID)
            )
        }
        allItems = model.items

        let selection = SwitcherSelection(count: windows.count, reverse: reverse)
        // Open without animating from the previous session's state.
        showSelection(selection.index, animated: false)
        self.selection = selection

        // A quick ⌘Tab can let go of ⌘ before this hot key is handled; no release
        // follows then. Switch at once, without drawing the switcher. A release
        // after this check still arrives as `.commandReleased`.
        let commandHeld = isCommandHeld()
        if let index = SwitcherRelease.windowToOpen(selection: selection, query: query, commandHeld: commandHeld) {
            Log.keys.debug("⌘ already released when the switcher opened; switching at once")
            commit(at: index)
            return true
        }
        commandDown = true

        // Take the keyboard now but draw only after a short hold: a quick ⌘Tab-Tab
        // switches without the full-screen stack flashing up (as macOS and AltTab).
        presenter.show()
        isShown = true
        onActiveChanged?(true)
        scheduleReveal()
        return true
    }

    private func scheduleReveal() {
        revealTask?.cancel()
        let sleep = self.sleep
        revealTask = Task { @MainActor [weak self] in
            await sleep(SwitcherReveal.holdDelay)
            guard let self, !Task.isCancelled else { return }
            self.revealTask = nil
            let commandHeld = self.isCommandHeld()
            switch SwitcherReveal.afterHold(selection: self.selection, query: self.query, commandHeld: commandHeld) {
            case .draw:
                self.reveal()
            case .open(let index):
                Log.keys.debug("⌘ released during the hold without a release event; switching")
                self.commit(at: index)
            case .closed:
                break
            }
        }
    }

    /// Makes the panel that `presenter.show()` ordered in invisible visible and clickable.
    private func reveal() {
        revealTask?.cancel()
        revealTask = nil
        guard isActive, !isDrawn else { return }
        isDrawn = true
        // Pictures memory holds go in first, so the stack appears with them.
        loadPreviews(lookAhead: true)
        presenter.draw()
    }

    private func showSelection(_ index: Int, animated: Bool) {
        guard !animated else {
            model.selection = index
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.selection = index }
    }

    /// Shows only the windows whose title, app or document contains every typed word.
    private func setQuery(_ newQuery: String) {
        query = newQuery
        let matches = allItems.filter { item in
            SwitcherFilter.matches(newQuery, fields: [item.title, item.appName, item.document ?? ""])
        }
        model.query = newQuery
        model.items = matches
        // The best match — the most recently used one — comes to the front.
        var newSelection = SwitcherSelection(count: matches.count, reverse: false)
        newSelection.select(0)
        selection = newSelection
        model.selection = newSelection.index
        if SwitcherReveal.drawsAtOnce(query: newQuery) { reveal() }
        loadPreviews(lookAhead: true)
    }

    private func step(_ delta: Int) {
        guard var selection else { return }
        selection.step(delta)
        self.selection = selection
        // Steps during the hold don't animate: the stack appears settled, not mid-spring.
        showSelection(selection.index, animated: isDrawn)
        loadPreviews(lookAhead: false)
    }

    private func commit(at index: Int) {
        guard isActive, model.items.indices.contains(index) else { return }
        let item = model.items[index]
        hide(returningToPreviousApp: false)
        focusWindow(item.windowID)
    }

    private func cancel() {
        guard isActive else { return }
        hide(returningToPreviousApp: true)
    }

    private func hide(returningToPreviousApp: Bool) {
        revealTask?.cancel()
        revealTask = nil
        isDrawn = false
        previewTasks.forEach { $0.cancel() }
        previewTasks = []
        askedPreviews = []
        let wasShown = isShown
        isShown = false
        if wasShown { presenter.hide(returningToPreviousApp: returningToPreviousApp) }
        selection = nil
        commandDown = false
        allWindows = []
        allItems = []
        query = ""
        model.query = ""
        model.thumbnails = [:]
        if wasShown { onActiveChanged?(false) }
    }

    /// Pictures memory already has appear with the stack; fresh ones are
    /// captured side by side, the windows nearest the front first. Called again
    /// on every step and filter change for the cards not asked for yet (see
    /// `SwitcherPreviews`); captures already running keep going. Nothing is
    /// captured before the switcher is drawn, so a quick hop takes no pictures.
    private func loadPreviews(lookAhead: Bool) {
        guard isDrawn else { return }
        let ids = SwitcherPreviews.toCapture(
            ids: model.items.map(\.windowID), selection: model.selection,
            visibleDepth: SwitcherStack.visibleDepth, asked: askedPreviews, lookAhead: lookAhead)
        guard !ids.isEmpty, PreviewProvider.shared.isAvailable else { return }
        askedPreviews.formUnion(ids)
        let wanted = ids.compactMap { id in allWindows.first { $0.id == id } }
        for window in wanted where model.thumbnails[window.id] == nil {
            if let cached = PreviewProvider.shared.cachedThumbnail(for: window.id) {
                model.thumbnails[window.id] = cached
            }
        }
        previewTasks += wanted.map { window in
            Task { @MainActor [weak self] in
                let image = await PreviewProvider.shared.thumbnail(for: window)
                // The switcher may have closed while capturing: drop the image then.
                guard !Task.isCancelled, let self, self.isActive, let image else { return }
                self.model.thumbnails[window.id] = image
            }
        }
    }
}
