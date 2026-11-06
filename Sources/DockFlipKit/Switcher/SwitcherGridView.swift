import AppKit
import SwiftUI

/// The ⌘Tab switcher in the style of Windows 11 Alt+Tab: one frosted panel in the
/// middle of the screen with a tile per window (its icon and title above its
/// picture), filling rows left to right. The selected tile is outlined; each ⌘Tab
/// moves the outline on, and releasing ⌘ opens that window. Same controller and
/// model as Flip 3D (`SwitcherView`); the layout rules are in `SwitcherGrid`.
struct SwitcherGridView: View {
    @ObservedObject var model: SwitcherModel

    var body: some View {
        GeometryReader { geo in
            let metrics = SwitcherGrid.Metrics(screen: geo.size)
            ZStack {
                // Windows 11 leaves the desktop as it is; a click beside the panel cancels.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.onCancel?() }

                VStack(spacing: 14) {
                    if !model.query.isEmpty {
                        SearchPill(query: model.query, count: model.items.count)
                    }
                    panel(metrics)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

extension SwitcherGridView {
    /// The frosted panel with the visible rows, or the no-match line while filtering.
    private func panel(_ metrics: SwitcherGrid.Metrics) -> some View {
        VStack(spacing: CGFloat(SwitcherGrid.spacing)) {
            if model.items.isEmpty {
                Text("No windows match")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            } else {
                rows(metrics)
            }
            if model.query.isEmpty {
                Text("Type to filter")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(CGFloat(SwitcherGrid.panelPadding))
        .frostedPanel(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        // Taps on the panel's own background must not fall through to cancel.
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {}
    }

    /// Only the rows around the selected tile (`SwitcherGrid.visibleRows`), so with
    /// 60 windows the panel builds a few rows of tiles, not 60.
    private func rows(_ metrics: SwitcherGrid.Metrics) -> some View {
        // Sized by each window's own shape, not its picture's, so tiles keep
        // their places when pictures arrive.
        let widths: [Double] = model.items.map { metrics.tileWidth(windowSize: $0.windowSize) }
        let allRows: [Range<Int>] = SwitcherGrid.rows(
            widths: widths, maxWidth: metrics.maxRowWidth, spacing: SwitcherGrid.spacing)
        let selectedRow: Int = SwitcherGrid.row(of: model.selection, in: allRows) ?? 0
        let shown: Range<Int> = SwitcherGrid.visibleRows(
            count: allRows.count, selectedRow: selectedRow, maxRows: metrics.maxRows)
        return VStack(spacing: CGFloat(SwitcherGrid.spacing)) {
            ForEach(Array(shown), id: \.self) { (row: Int) in
                HStack(spacing: CGFloat(SwitcherGrid.spacing)) {
                    ForEach(Array(allRows[row]), id: \.self) { (index: Int) in
                        tile(index, width: widths[index], pictureHeight: metrics.pictureHeight)
                    }
                }
            }
        }
    }

    private func tile(_ index: Int, width: Double, pictureHeight: Double) -> some View {
        let item: SwitcherItem = model.items[index]
        return GridTile(
            item: item,
            thumbnail: model.thumbnails[item.windowID],
            isSelected: index == model.selection,
            width: CGFloat(width),
            pictureHeight: CGFloat(pictureHeight)
        )
        .onTapGesture { model.onPick?(index) }
    }
}

/// One window in the grid: its icon and title, and under them its picture when
/// previews are on, or its icon on a wash of the app's colour when they are off.
struct GridTile: View {
    let item: SwitcherItem
    let thumbnail: NSImage?
    let isSelected: Bool
    let width: CGFloat
    let pictureHeight: CGFloat

    private static let corner: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AppIconView(icon: item.icon, size: 16)
                Text(verbatim: item.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .frame(height: 18)

            picture
                .frame(height: pictureHeight)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(CGFloat(SwitcherGrid.tilePadding))
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .contentShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.appName): \(item.title)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    @ViewBuilder
    private var picture: some View {
        if let thumbnail {
            ThumbnailView(image: thumbnail, windowSize: item.windowSize, icon: item.icon, showsIcon: false)
        } else {
            ZStack {
                Color(nsColor: .windowBackgroundColor).opacity(0.7)
                LinearGradient(
                    colors: [item.tint.opacity(0.28), item.tint.opacity(0.06)],
                    startPoint: .top, endPoint: .bottom
                )
                VStack(spacing: 6) {
                    AppIconView(icon: item.icon, size: min(64, pictureHeight * 0.45))
                        .opacity(item.isMinimized ? 0.6 : 1)
                    if item.neverPictured {
                        Label("No picture, for privacy", systemImage: "lock")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if item.isMinimized || item.isOnOtherSpace {
                        Text(verbatim: item.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 6)
            }
        }
    }
}
