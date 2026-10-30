import AppKit
import ApplicationServices

/// A window as DockFlip sees it. Frames are in AX space (top-left origin).
public struct WindowSnapshot: Identifiable {
    public let id: CGWindowID
    public let pid: pid_t
    public let bundleID: String?
    public let appName: String
    public let icon: NSImage?
    public var title: String
    public var frame: CGRect
    public var isMinimized: Bool
    public var isAppHidden: Bool
    /// File name of the document shown in the window, when the app reports one.
    public var document: String?
    /// On another Space (another desktop, or a full-screen app). Set by `switcherWindows()`.
    public var isOnOtherSpace = false
}
