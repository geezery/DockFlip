/// When the snap preview says that macOS's own edge tiling is on too. Someone
/// who sees a window snap twice may never open the menu bar menu, so the first
/// drag snap after launch with tiling on points there, once per launch.
struct EdgeTilingHint {
    /// The hint has been shown in this launch.
    private(set) var shown = false
    /// This drag's answer, once a snap zone has asked.
    private var thisDrag: Bool?

    /// A mouse down: the next drag asks afresh.
    mutating func newDrag() {
        thisDrag = nil
    }

    /// Whether the preview of a drag now over a snap zone carries the hint.
    /// `tilingOn` syncs macOS's preferences (one IPC), so it is read at most once
    /// per drag, and never again once the hint has been shown.
    mutating func showsHint(tilingOn: () -> Bool) -> Bool {
        if let thisDrag { return thisDrag }
        let show = !shown && tilingOn()
        shown = shown || show
        thisDrag = show
        return show
    }
}
