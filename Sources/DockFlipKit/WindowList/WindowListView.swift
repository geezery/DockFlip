import AppKit
import SwiftUI

// The views of the Dock window list. `WindowListPopup` owns the model and the
// panel; these views only draw the model and call back into the popup.
//
// Three layouts, picked by `WindowListLayout`:
// - a list of windows (title, mini-map or, with previews on, a small picture,
//   state), tabs hanging under browser windows;
// - with previews on: a row of picture cards;
// - with previews on and tabs, or more than five windows: the list, with one
//   big picture underneath (`PeekPane`).

/// The whole popup: the app's name, then the windows.
struct WindowListView: View {
    @ObservedObject var model: WindowListModel
    let popup: WindowListPopup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: model.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: model.rows.isEmpty ? 44 : 36, alignment: .center)

            if !model.rows.isEmpty {
                if model.usesCards {
                    HStack(spacing: 4) {
                        ForEach(model.rows) { row in
                            WindowCardView(row: row, thumbnail: model.thumbnails[row.id], model: model, popup: popup)
                        }
                    }
                    .padding(.horizontal, 6)
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            ForEach(model.rows) { row in
                                WindowRowView(row: row, model: model, popup: popup)
                                let isExpanded = model.expanded.contains(row.id)
                                let visible = WindowListLayout.visibleTabs(of: row, expanded: isExpanded)
                                if !visible.tabs.isEmpty {
                                    let fold = WindowListLayout.foldControl(of: row, expanded: isExpanded)
                                    TabListView(row: row, tabs: visible.tabs, fold: fold, model: model, popup: popup)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .scrollIndicators(.never)
                    // Without scroll bars, windows past the tenth are a secret: say how many.
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.visibleRect.maxY.rounded()
                    } action: { _, bottom in
                        model.listBottom = bottom
                    }
                    // A new scroll view for each app's list: it starts at the top.
                    .id(model.listID)
                    .overlay(alignment: .bottom) {
                        let below = model.windowsBelow
                        if below > 0 {
                            MoreWindowsCue(count: below, previews: model.showsPreviews)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: model.windowsBelow > 0)
                    if model.showsPreviews {
                        PeekPane(model: model, popup: popup)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Pictures need a calm, nearly solid backdrop; the lighter glass suits the plain list.
        .frostedBackground(
            model.showsPreviews ? .thickMaterial : .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        // A window scrolled to the panel's foot, or the cue's fade, stays inside the rounded corners.
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(FrostedEdge(shape: RoundedRectangle(cornerRadius: 12, style: .continuous)))
    }
}

/// "4 more windows" over a fade at the foot of a list that scrolls. Not a
/// button: the mouse goes through it, so the wheel over it still scrolls the
/// list and the window under it can still be clicked.
struct MoreWindowsCue: View {
    let count: Int
    /// The panel's backdrop is thicker with pictures; the fade matches it.
    let previews: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: count == 1 ? L("1 more window") : String(format: L("%ld more windows"), count))
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .accessibilityHidden(true)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: WindowListLayout.moreCueHeight)
        .background(
            FrostedFill(material: previews ? .thickMaterial : .regularMaterial, shape: Rectangle())
                .mask(LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.6)],
                    startPoint: .top, endPoint: .bottom
                ))
        )
        .allowsHitTesting(false)
    }
}

/// One window in the list: mini-map, title, state, close button.
struct WindowRowView: View {
    let row: WindowListRow
    @ObservedObject var model: WindowListModel
    let popup: WindowListPopup

    private var hovering: Bool { model.hoveredRow == row.id }

    var body: some View {
        HStack(spacing: 10) {
            RowPicture(row: row, thumbnail: model.showsPreviews ? model.thumbnails[row.id] : nil,
                       pending: model.showsPreviews && row.expectsPicture)
                .frame(width: 52, height: 33)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: row.isActive ? 1.5 : 0)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title)
                    .font(.system(size: 13, weight: row.isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if row.isActive {
                    // The window in front: said in words too, not only with weight.
                    Text(verbatim: row.tabs.count > 1 ? L("Active window") + " · " + TabSummary.text(for: row.tabs) : L("Active window"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                } else if row.isMinimized {
                    Text("Minimized").font(.system(size: 11)).foregroundStyle(.secondary)
                } else if row.tabs.count > 1 {
                    Text(verbatim: TabSummary.text(for: row.tabs))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if row.isOnOtherSpace {
                    Text("On another desktop").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Button {
                popup.close(row.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.35)
            .accessibilityLabel(Text("Close window"))
        }
        .padding(.horizontal, 8)
        .frame(height: WindowListLayout.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity((row.isActive ? 0.14 : 0) + (hovering ? 0.10 : 0)))
        )
        // Windows 11's active marker: a short accent pill at the edge.
        .overlay(alignment: .leading) {
            if row.isActive {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 20)
                    .offset(x: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { model.setHovered(row.id, $0) }
        .onTapGesture { popup.pick(row.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The small picture at the front of a window row: the window itself when
/// thumbnails are on and its picture is in, else the mini-map of where it sits.
/// Two maximized windows have identical mini-maps, so with thumbnails on the
/// real picture is what tells them apart. It is the same picture the peek pane
/// shows, so no capture is added for it.
struct RowPicture: View {
    let row: WindowListRow
    let thumbnail: NSImage?
    /// The picture is on its way: a calm placeholder, not the mini-map, until it is in.
    var pending = false

    var body: some View {
        if thumbnail != nil || pending {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                if let thumbnail {
                    ThumbnailView(image: thumbnail, windowSize: row.windowSize, icon: row.icon, cornerRadius: 3)
                        .transition(.opacity)
                } else {
                    PicturePending(icon: row.icon, iconSize: 14)
                }
            }
            .animation(.easeOut(duration: 0.15), value: thumbnail != nil)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityHidden(true)
        } else {
            Minimap(rect: row.minimap, isMinimized: row.isMinimized, tint: row.tint, icon: row.icon)
        }
    }
}

/// Where a window's picture goes while it loads: the app's icon, dimmed, on the
/// card's plain fill. Nothing in it looks like a picture, so nothing "wrong"
/// shows before the real one fades in.
struct PicturePending: View {
    let icon: NSImage?
    var iconSize: CGFloat = 28

    var body: some View {
        AppIconView(icon: icon, size: iconSize)
            .opacity(0.35)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

/// A window as a picture card (previews on, apps without tabs).
struct WindowCardView: View {
    let row: WindowListRow
    let thumbnail: NSImage?
    @ObservedObject var model: WindowListModel
    let popup: WindowListPopup

    private var hovering: Bool { model.hoveredRow == row.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AppIconView(icon: row.icon, size: 16)
                Text(verbatim: row.title)
                    .font(.system(size: 12, weight: row.isActive ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if row.tabs.count > 1 {
                    Text(verbatim: "\(row.tabs.count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.1), in: Capsule())
                        .help(Text(verbatim: TabSummary.text(for: row.tabs)))
                }
                Button {
                    popup.close(row.id)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0.35)
                .accessibilityLabel(Text("Close window"))
            }
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06))
                if let thumbnail {
                    ThumbnailView(image: thumbnail, windowSize: row.windowSize, icon: row.icon, showsIcon: false)
                        .transition(.opacity)
                } else if row.expectsPicture && model.showsPreviews {
                    PicturePending(icon: row.icon)
                } else {
                    Minimap(rect: row.minimap, isMinimized: row.isMinimized, tint: row.tint, icon: row.icon)
                }
                if row.neverPictured && model.showsPreviews {
                    VStack {
                        Spacer(minLength: 0)
                        Label("No picture, for privacy", systemImage: "lock")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 6)
                    }
                }
            }
            .animation(.easeOut(duration: 0.15), value: thumbnail != nil)
            .frame(width: 188, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(6)
        .frame(width: WindowListLayout.cardWidth - 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity((row.isActive ? 0.14 : 0) + (hovering ? 0.10 : 0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: row.isActive ? 2 : 0)
        )
        .contentShape(Rectangle())
        .onHover { model.setHovered(row.id, $0) }
        .onTapGesture { popup.pick(row.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// One picture under a browser's tab list: the window under the mouse, else the
/// active window, else the most recent one. Click it to bring that window forward.
struct PeekPane: View {
    @ObservedObject var model: WindowListModel
    let popup: WindowListPopup

    var body: some View {
        let row = model.peekWindow.flatMap { id in model.rows.first { $0.id == id } }
            ?? model.rows.first { $0.isActive }
            ?? model.rows.first
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if let row {
                if let image = model.thumbnails[row.id] {
                    ThumbnailView(image: image, windowSize: row.windowSize, icon: row.icon, cornerRadius: 6)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        .padding(8)
                        .id(row.id)
                        .transition(.opacity)
                } else if row.expectsPicture {
                    PicturePending(icon: row.icon, iconSize: 40)
                } else {
                    Minimap(rect: row.minimap, isMinimized: row.isMinimized, tint: row.tint, icon: row.icon)
                        .padding(14)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: model.hoveringPeek ? 2 : 0)
        )
        .animation(.easeOut(duration: 0.15), value: row?.id)
        .animation(.easeOut(duration: 0.15), value: row.map { model.thumbnails[$0.id] != nil })
        .frame(height: WindowListLayout.peekHeight)
        .contentShape(Rectangle())
        .onHover { model.hoveringPeek = $0 }
        .onTapGesture {
            if let row { popup.pick(row.id) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row?.title ?? ""))
        .accessibilityAddTraits(.isButton)
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }
}
