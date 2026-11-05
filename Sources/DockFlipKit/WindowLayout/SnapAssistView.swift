import AppKit
import SwiftUI

/// The Snap Assist cards over the region left after a snap: a frosted plate the
/// size of the region, with a card per window in even rows. The cards are the
/// ⌘Tab grid's (`GridTile`), so a window looks the same in both.
struct SnapAssistView: View {
    @ObservedObject var model: SnapAssistModel

    var body: some View {
        let grid: SnapAssistGrid = model.grid
        let rows: [Range<Int>] = grid.rows(count: model.items.count)
        VStack(alignment: .leading, spacing: CGFloat(SnapAssistGrid.spacing)) {
            ForEach(Array(rows.indices), id: \.self) { (row: Int) in
                HStack(spacing: CGFloat(SnapAssistGrid.spacing)) {
                    ForEach(Array(rows[row]), id: \.self) { (index: Int) in
                        tile(index, grid: grid)
                    }
                }
            }
        }
        .padding(CGFloat(SnapAssistGrid.margin) - 6) // the panel already sits 6 pt inside the region
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frostedPanel(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func tile(_ index: Int, grid: SnapAssistGrid) -> some View {
        let item: SwitcherItem = model.items[index]
        return GridTile(
            item: item,
            thumbnail: model.thumbnails[item.windowID],
            isSelected: index == model.selection,
            width: CGFloat(grid.tileWidth),
            pictureHeight: CGFloat(grid.pictureHeight)
        )
        .onTapGesture { model.onPick?(index) }
        // VoiceOver's press, which a tap gesture alone does not answer.
        .accessibilityAction { model.onPick?(index) }
        .onHover { inside in
            // As on Windows, the pointer moves the outline too, so Return picks what it points at.
            if inside { model.selection = index }
        }
    }
}
