import AppKit
import SwiftUI

/// What the window list shows for one Dock icon. Built by its source (the Dock)
/// each time the list is drawn, so it is always current.
struct WindowListItem {
    let bundleID: String
    let name: String
    /// The app's windows, most recently used first; all Spaces, minimized included.
    let windows: [WindowSnapshot]
    let isNotResponding: Bool
}

/// The screen edge the Dock sits on; the list opens away from it.
enum DockEdge {
    case bottom, left, right
}

/// Where the window list gets its content and its position.
@MainActor
protocol WindowListSource: AnyObject {
    /// nil when there is nothing to list (the app has no windows).
    func windowListItem(for key: String) -> WindowListItem?
    /// The icon the list belongs to, in screen (Cocoa) coordinates.
    func anchor(for key: String) -> NSRect?
    var dockEdge: DockEdge { get }
}

/// One window in the list, ready to draw.
struct WindowListRow: Identifiable {
    let id: CGWindowID
    let title: String
    let icon: NSImage?
    let minimap: CGRect?
    let isMinimized: Bool
    let isOnOtherSpace: Bool
    let isActive: Bool
    /// The app's colour, from its icon; colours the mini-map.
    let tint: Color
    /// Browser tabs of this window, once read (empty for other apps).
    let tabs: [BrowserTab]
    /// The window's size in points; places the app's icon over its buttons in a thumbnail.
    var windowSize: CGSize = .zero
    /// A window thumbnails never picture (`NeverPictured`); its card says so when previews are on.
    var neverPictured = false
    /// With previews on: the window has a picture or gets one when asked, so
    /// while it loads the card shows a calm placeholder, not the mini-map.
    var expectsPicture = false
}

/// State the views draw. Hover state lives here, not in SwiftUI's @State: @State
/// is a macro, and the Command Line Tools cannot expand macros.
@MainActor
final class WindowListModel: ObservableObject {
    @Published var title = ""
    @Published var rows: [WindowListRow] = []
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    @Published var showsPreviews = false
    @Published var hoveredRow: CGWindowID?
    @Published var hoveredTab: String?
    /// The window whose "Show all N tabs" or "Show fewer" line the mouse is on.
    @Published var hoveredFold: CGWindowID?
    /// The window whose picture the peek pane shows (previews on, with tabs).
    @Published var peekWindow: CGWindowID? {
        didSet { if let peekWindow, peekWindow != oldValue { peekChanged?(peekWindow) } }
    }
    /// Called when the peek pane turns to another window, so the popup can
    /// capture a window that the first batch of pictures left out.
    var peekChanged: ((CGWindowID) -> Void)?
    /// The mouse is on the peek pane's picture.
    @Published var hoveringPeek = false
    /// Windows whose long tab list is shown in full.
    @Published var expanded = Set<CGWindowID>()
    /// The lowest point of the list on screen, measured from the list's top, as
    /// the scroll view last reported it; nil until it has. Decides "N more windows".
    @Published var listBottom: CGFloat?
    /// The scroll view's identity: a new one each time a list starts, so it
    /// opens at its top, not where the last app's list was scrolled to.
    @Published private(set) var listID = 0

    var hasTabs: Bool { rows.contains { $0.tabs.count > 1 } }
    var usesCards: Bool { WindowListLayout.usesCards(rows: rows, previews: showsPreviews) }
    /// Windows below the bottom of the list. Before the scroll view reports, the
    /// list is at its top, so the bottom is the list's own height.
    var windowsBelow: Int {
        let bottom = listBottom ?? WindowListLayout.listHeight(rows: rows, expanded: expanded, previews: showsPreviews)
        return WindowListLayout.windowsBelow(rows: rows, expanded: expanded, visibleBottom: bottom)
    }

    /// Another app's list, or the list opened again: the popup keeps one panel
    /// and one scroll view for every app, so nothing of the last list may carry
    /// over, least of all its scroll offset, which would hide the most recent windows.
    func startNewList() {
        // A click hides the panel before the mouse leaves the row, so no exit
        // arrives: the row would still be lit when the list opens again.
        hoveredRow = nil
        hoveredTab = nil
        hoveredFold = nil
        expanded = []
        peekWindow = nil
        hoveringPeek = false
        thumbnails = [:]
        listBottom = nil
        listID += 1
    }

    func setHovered(_ id: CGWindowID, _ inside: Bool) {
        if inside {
            hoveredRow = id
            peekWindow = id
        } else if hoveredRow == id {
            hoveredRow = nil
        }
    }

    func setHoveredTab(_ id: String, window: CGWindowID, _ inside: Bool) {
        if inside {
            hoveredTab = id
            peekWindow = window
        } else if hoveredTab == id {
            hoveredTab = nil
        }
    }

    func setHoveredFold(_ window: CGWindowID, _ inside: Bool) {
        if inside {
            hoveredFold = window
        } else if hoveredFold == window {
            hoveredFold = nil
        }
    }
}
