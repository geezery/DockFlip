import AppKit

/// A running app with no open window, shown in ⌘Tab as an app card when no
/// window is open at all, so the keyboard still reaches it (macOS's own ⌘Tab
/// is turned off while DockFlip's is on).
struct SwitcherApp {
    let pid: pid_t
    let name: String
    let icon: NSImage?
}
