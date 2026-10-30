import Foundation

/// The cleaner's "last used" rule, apart from AppKit so it can be tested.
enum UsageDates {
    /// Windows seen for the first time count from `now`; the active window is used `now`.
    /// `tracked` is every window DockFlip tracks, on any Space: this runs on every
    /// window move and resize, so its caller reads what the registry already holds
    /// rather than asking the window server.
    static func stamp<ID: Hashable>(_ dates: inout [ID: Date], tracked: some Sequence<ID>, active: ID?, now: Date) {
        for id in tracked where dates[id] == nil {
            dates[id] = now
        }
        if let active { dates[active] = now }
    }
}
