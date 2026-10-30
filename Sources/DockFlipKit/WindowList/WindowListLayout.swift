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
    /// "4 more windows" at the foot of a list that scrolls. Taller than the
    /// list's 10-point bottom margin; the list grows by the difference, so the
    /// cue covers only the top of the eleventh window, never the tenth.
    static let moreCueHeight: CGFloat = 24

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
        let list = listHeight(rows: rows, expanded: expanded, previews: previews)
        if previews {
            // The tab list on top, one picture of the window under the mouse below it.
            return NSSize(width: tabListWidth, height: 36 + list + peekHeight + 6)
        }
        return NSSize(width: hasTabs ? tabListWidth : listWidth, height: 36 + list)
    }

    /// The scrolling list under the app's name: room for up to ten windows,
    /// capped so the whole panel (with its picture, if any) stays within `maxListHeight`.
    static func listHeight(rows: [WindowListRow], expanded: Set<CGWindowID>, previews: Bool) -> CGFloat {
        var height: CGFloat = 10
        for row in rows.prefix(maxVisibleRows) {
            height += blockHeight(of: row, expanded: expanded.contains(row.id))
        }
        if rows.count > maxVisibleRows {
            height += moreCueHeight - 10
        }
        let cap = previews ? maxListHeight - peekHeight : maxListHeight
        return min(36 + height, cap) - 36
    }

    /// One window in the list: its row, and the tabs listed under it.
    static func blockHeight(of row: WindowListRow, expanded: Bool) -> CGFloat {
        let (tabs, hidden) = visibleTabs(of: row, expanded: expanded)
        guard !tabs.isEmpty else { return rowHeight }
        return rowHeight + CGFloat(tabs.count + (hidden > 0 ? 1 : 0)) * tabRowHeight + tabListPadding
    }

    /// How many windows are wholly or partly below `visibleBottom`, the lowest
    /// point of the list on screen, measured from the list's top. The cue says
    /// this number; scrolled to the end it is 0 and the cue goes away.
    static func windowsBelow(rows: [WindowListRow], expanded: Set<CGWindowID>, visibleBottom: CGFloat) -> Int {
        var bottom: CGFloat = 0
        for (index, row) in rows.enumerated() {
            bottom += blockHeight(of: row, expanded: expanded.contains(row.id))
            // Half a point of slack: scroll offsets are fractional.
            if bottom > visibleBottom + 0.5 { return rows.count - index }
        }
        return 0
    }
}
