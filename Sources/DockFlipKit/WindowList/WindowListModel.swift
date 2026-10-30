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
    /// The window whose picture the peek pane shows (previews on, with tabs).
    @Published var peekWindow: CGWindowID?
    /// The mouse is on the peek pane's picture.
    @Published var hoveringPeek = false
    /// Windows whose long tab list is shown in full.
    @Published var expanded = Set<CGWindowID>()

    var hasTabs: Bool { rows.contains { $0.tabs.count > 1 } }
    var usesCards: Bool { WindowListLayout.usesCards(rows: rows, previews: showsPreviews) }

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
}
