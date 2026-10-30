import AppKit

/// Sizes. The panel's size is computed here, not by SwiftUI, so it is known
/// before anything is drawn and the list never jumps.
enum WindowListLayout {
    static let listWidth: CGFloat = 320
    static let tabListWidth: CGFloat = 400
    static let rowHeight: CGFloat = 48
    static let maxVisibleRows = 10
    static let cardWidth: CGFloat = 212
    static let cardHeight: CGFloat = 156
    static let tabRowHeight: CGFloat = 28
    static let tabListPadding: CGFloat = 6
    /// Longer tab lists are folded behind "Show all N tabs".
    static let foldedTabs = 8
    static let maxListHeight: CGFloat = 600
    /// The picture under the tab list when previews are on.
    static let peekHeight: CGFloat = 230

    /// The tabs listed under a window, and how many are folded away.
    static func visibleTabs(of row: WindowListRow, expanded: Bool) -> (tabs: [BrowserTab], hidden: Int) {
        guard row.tabs.count > 1 else { return ([], 0) }
        if expanded || row.tabs.count <= foldedTabs { return (row.tabs, 0) }
        var shown = Array(row.tabs.prefix(foldedTabs - 1))
        // The tab you are on is always listed.
        if let selected = row.tabs.first(where: \.isSelected), !shown.contains(where: { $0.id == selected.id }) {
            shown.append(selected)
        }
        return (shown, row.tabs.count - shown.count)
    }

    /// Picture cards side by side, while they fit (five); otherwise the list,
    /// with one picture underneath.
    static let maxCards = 5

    static func usesCards(rows: [WindowListRow], previews: Bool) -> Bool {
        previews && rows.count <= maxCards && !rows.contains { $0.tabs.count > 1 }
    }

    static func size(rows: [WindowListRow], expanded: Set<CGWindowID>, previews: Bool) -> NSSize {
        if rows.isEmpty {
            return NSSize(width: 220, height: 44)
        }
        let hasTabs = rows.contains { $0.tabs.count > 1 }
        if usesCards(rows: rows, previews: previews) {
            let columns = rows.count
            return NSSize(width: CGFloat(columns) * cardWidth + 16, height: 36 + cardHeight + 12)
        }
        var height: CGFloat = 36 + 10
        for row in rows.prefix(maxVisibleRows) {
            height += rowHeight
            let (tabs, hidden) = visibleTabs(of: row, expanded: expanded.contains(row.id))
            guard !tabs.isEmpty else { continue }
            height += CGFloat(tabs.count + (hidden > 0 ? 1 : 0)) * tabRowHeight + tabListPadding
        }
        if previews {
            // The tab list on top, one picture of the window under the mouse below it.
            return NSSize(width: tabListWidth, height: min(height, maxListHeight - peekHeight) + peekHeight + 6)
        }
        return NSSize(width: hasTabs ? tabListWidth : listWidth, height: min(height, maxListHeight))
    }
}
