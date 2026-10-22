import AppKit
import SwiftUI

// The views of the Dock window list. `WindowListPopup` owns the model and the
// panel; these views only draw the model and call back into the popup.
//
// Three layouts, picked by `WindowListLayout`:
// - a list of windows (title, mini-map, state), tabs hanging under browser windows;
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
                                let visible = WindowListLayout.visibleTabs(of: row, expanded: model.expanded.contains(row.id))
                                if !visible.tabs.isEmpty {
                                    TabListView(row: row, tabs: visible.tabs, hidden: visible.hidden, model: model, popup: popup)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .scrollIndicators(.never)
                    if model.showsPreviews {
                        PeekPane(model: model)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Pictures need a calm, nearly solid backdrop; the lighter glass suits the plain list.
        .background(
            model.showsPreviews ? AnyShapeStyle(.thickMaterial) : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
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
            Minimap(rect: row.minimap, isMinimized: row.isMinimized, tint: row.tint, icon: row.icon)
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
                    Image(nsImage: thumbnail).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                } else {
                    Minimap(rect: row.minimap, isMinimized: row.isMinimized, tint: row.tint, icon: row.icon)
                }
            }
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
/// active window, else the most recent one.
struct PeekPane: View {
    @ObservedObject var model: WindowListModel

    var body: some View {
        let row = model.peekWindow.flatMap { id in model.rows.first { $0.id == id } }
            ?? model.rows.first { $0.isActive }
            ?? model.rows.first
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if let row {
                if let image = model.thumbnails[row.id] {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        .padding(8)
                        .id(row.id)
                        .transition(.opacity)
                } else {
                    Minimap(rect: row.minimap, isMinimized: row.isMinimized, tint: row.tint, icon: row.icon)
                        .padding(14)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: row?.id)
        .frame(height: WindowListLayout.peekHeight)
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }
}
