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
    /// Flip 3D or the Windows 11 grid, read as the switcher opens.
    private let style: @MainActor () -> SwitcherStyle
    /// Saves the look picked with the switcher's toggle, as the Settings choice.
    private let setStyle: @MainActor (SwitcherStyle) -> Void
    /// False when the organization's profile sets the look: no toggle then.
    private let canChangeStyle: @MainActor () -> Bool
    /// Running apps with no open window, listed only when there are no windows at all.
    private let windowlessApps: @MainActor () -> [SwitcherApp]
    /// Brings a windowless app forward, asking it to reopen a window.
    private let openApp: @MainActor (pid_t) -> Void
    private let presenter: any SwitcherPresenter
    private let model: SwitcherModel
    private var selection: SwitcherSelection?
    /// Every window of this session; `model.items` holds the ones matching the filter.
    private var allWindows: [WindowSnapshot] = []
    private var allItems: [SwitcherItem] = []
    /// Typed filter. Not empty means "search mode": releasing ⌘ no longer
    /// switches, Return does. Cleared whenever the switcher closes.
    private var query = ""
    /// Whether the next ⌘ release switches (`SwitcherCommandArm`): only the first
    /// release after opening with ⌘ held, or after ⌘ is pressed again, does.
    /// While ⌘ is up, only Return, a click or holding ⌘ again and letting go opens a window.
    private var commandArm = SwitcherCommandArm()
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
            style: { Settings.shared.switcherStyle },
            setStyle: { Settings.shared.switcherStyle = $0 },
            canChangeStyle: { !Settings.shared.switcherStyleManaged },
            windowlessApps: { registry.windowlessApps() },
            openApp: { registry.openApp(pid: $0) },
            presenter: nil
        )
        // On the next turn, so launch itself is not held up by it.
        Task { @MainActor [weak self] in self?.prepare() }
    }

    /// Builds the panel ahead of the first ⌘Tab (`SwitcherPresenter.prepare`).
    func prepare() {
        // Built in the chosen look, so the first ⌘Tab of a grid user is not the one building it.
        model.style = style()
        model.canChangeStyle = canChangeStyle()
        presenter.prepare()
    }

    /// Tests pass fakes; `presenter` nil means the real panel.
    init(
        switcherWindows: @escaping @MainActor () -> [WindowSnapshot],
        focusWindow: @escaping @MainActor (CGWindowID) -> Void,
        isCommandHeld: @escaping @MainActor () -> Bool,
        sleep: @escaping @MainActor (Duration) async -> Void,
        style: @escaping @MainActor () -> SwitcherStyle = { .flip3D },
        setStyle: @escaping @MainActor (SwitcherStyle) -> Void = { _ in },
        canChangeStyle: @escaping @MainActor () -> Bool = { true },
        windowlessApps: @escaping @MainActor () -> [SwitcherApp] = { [] },
        openApp: @escaping @MainActor (pid_t) -> Void = { _ in },
        presenter: (any SwitcherPresenter)?
    ) {
        let model = SwitcherModel()
        self.windowlessApps = windowlessApps
        self.openApp = openApp
        self.switcherWindows = switcherWindows
        self.focusWindow = focusWindow
        self.isCommandHeld = isCommandHeld
        self.sleep = sleep
        self.style = style
        self.setStyle = setStyle
        self.canChangeStyle = canChangeStyle
        self.model = model
        self.presenter = presenter ?? SwitcherPanel(model: model)
        model.onPick = { [weak self] index in self?.commit(at: index) }
        model.onCancel = { [weak self] in self?.cancel() }
        model.onChangeStyle = { [weak self] style in self?.changeStyle(to: style) }
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
            guard commandArm.released() else { return false }
            if let index = SwitcherRelease.windowToOpen(selection: selection, query: query, commandHeld: false) {
                commit(at: index)
            }
            return false
        case .commandPressed:
            // ⌘ held again, say after letting go of it to filter: its release
            // switches once more, unless something is typed by then. The panel's
            // monitor and the flags tap both send it, so a copy can come in after
            // ⌘ is already up again: only the live state re-arms.
            if isActive { commandArm.pressed(commandHeld: isCommandHeld()) }
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
        // ⌘Tab is ours and macOS's own is off, so with every window closed it
        // must still reach the running apps: list them as app cards instead.
        let apps = windows.isEmpty ? windowlessApps() : []
        guard !windows.isEmpty || !apps.isEmpty else { return false }

        allWindows = windows
        let previews = PreviewProvider.shared.isAvailable
        query = ""
        model.query = ""
        model.thumbnails = [:]
        model.style = style()
        model.canChangeStyle = canChangeStyle()
        let windowItems = windows.map { SwitcherItem(window: $0, previews: previews) }
        model.items = apps.map { Self.appCard($0) } + windowItems
        allItems = model.items

        let selection = SwitcherSelection(count: model.items.count, reverse: reverse)
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
        commandArm.open(commandHeld: commandHeld)

        // Take the keyboard now but draw only after a short hold: a quick ⌘Tab-Tab
        // switches without the full-screen stack flashing up (as macOS and AltTab).
        presenter.show()
        isShown = true
        onActiveChanged?(true)
        // Pictures load from the press, not from the draw 150 ms later: memory's
        // are unpacked and the windows worked in since are captured while the
        // stack waits, so it appears with them.
        loadPreviews(lookAhead: true)
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

    /// The switcher's style toggle: redraws the open switcher in the other look,
    /// keeping its windows, filter and selected window, and saves the look for the
    /// next ⌘Tab. Internal, not private, so tests can click it.
    func changeStyle(to newStyle: SwitcherStyle) {
        guard isActive, model.canChangeStyle, newStyle != model.style else { return }
        Log.keys.debug("Switcher style changed from the switcher: \(newStyle.rawValue, privacy: .public)")
        setStyle(newStyle)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.style = newStyle }
        // The grid shows other windows than the stack's front cards: ask for their pictures.
        loadPreviews(lookAhead: true)
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
        if let pid = item.appPID {
            openApp(pid)
        } else {
            focusWindow(item.windowID)
        }
    }

    private static func appCard(_ app: SwitcherApp) -> SwitcherItem {
        SwitcherItem(
            windowID: 0, title: app.name, appName: app.name, icon: app.icon,
            minimap: nil, isMinimized: false, isOnOtherSpace: false, document: nil,
            screenName: nil, sizeText: "", windowSize: .zero, tint: .gray,
            neverPictured: false, appPID: app.pid
        )
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
        commandArm.reset()
        allWindows = []
        allItems = []
        query = ""
        model.query = ""
        model.thumbnails = [:]
        if wasShown { onActiveChanged?(false) }
    }

    /// Pictures memory already has appear with the stack; windows whose picture
    /// is out of date are captured (`PreviewProvider`), the ones nearest the front
    /// first. Called as ⌘Tab is pressed and again on every step and filter change
    /// for the cards not asked for yet (see `SwitcherPreviews`); loads already
    /// running keep going.
    private func loadPreviews(lookAhead: Bool) {
        guard isShown, PreviewProvider.shared.isAvailable else { return }
        let ids = previewsToCapture(lookAhead: lookAhead)
        guard !ids.isEmpty else { return }
        askedPreviews.formUnion(ids)
        let wanted = ids.compactMap { id in allWindows.first { $0.id == id } }
        // The grid's tiles are small; the stack's front card is large.
        let size = model.style == .grid ? SwitcherGrid.picturePixelSize : Int(PreviewProvider.maxPixelWidth)
        previewTasks += wanted.map { window in
            Task { @MainActor [weak self] in
                // A step to a card puts it ahead of the look-ahead ones.
                await PreviewProvider.shared.loadPicture(of: window, maxPixelSize: size, urgent: !lookAhead) { image in
                    // The switcher may have closed meanwhile: drop the image then.
                    guard let self, self.isActive else { return }
                    self.model.thumbnails[window.id] = image
                }
            }
        }
    }

    /// The stack shows the cards near the front (`SwitcherStack`); the grid shows
    /// a few rows of tiles at once, so it asks for the windows around the
    /// selected one, a bigger batch, on every step.
    private func previewsToCapture(lookAhead: Bool) -> [CGWindowID] {
        let ids = model.items.map(\.windowID)
        switch model.style {
        case .flip3D:
            return SwitcherPreviews.toCapture(
                ids: ids, selection: model.selection,
                visibleDepth: SwitcherStack.visibleDepth, asked: askedPreviews, lookAhead: lookAhead)
        case .grid:
            return SwitcherPreviews.toCaptureAround(
                ids: ids, selection: model.selection, asked: askedPreviews, limit: SwitcherGrid.previewBatch)
        }
    }
}
