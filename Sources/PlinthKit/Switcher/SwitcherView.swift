import AppKit
import SwiftUI

struct SwitcherItem: Identifiable {
    let id: CGWindowID
    let title: String
    let appName: String
    let icon: NSImage?
    /// Window outline as fractions of its screen (top-left origin), for the mini-map.
    let minimap: CGRect?
    let isMinimized: Bool
}

@MainActor
final class SwitcherModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var selection = 0
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    var onPick: ((Int) -> Void)?
}

enum SwitcherLayout {
    static let tileWidth: CGFloat = 148
    static let tileHeight: CGFloat = 156
    static let spacing: CGFloat = 10
    static let padding: CGFloat = 16
    static let maxColumns = 7
    static let cornerRadius: CGFloat = 20

    static func columns(for count: Int) -> Int {
        max(1, min(count, maxColumns))
    }

    static func panelSize(itemCount: Int) -> NSSize {
        let columns = Self.columns(for: itemCount)
        let rows = max(1, Int((Double(itemCount) / Double(maxColumns)).rounded(.up)))
        let width = CGFloat(columns) * tileWidth + CGFloat(columns - 1) * spacing + padding * 2
        let height = CGFloat(rows) * tileHeight + CGFloat(rows - 1) * spacing + padding * 2
        return NSSize(width: width, height: height)
    }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    var body: some View {
        let columns = Array(
            repeating: GridItem(.fixed(SwitcherLayout.tileWidth), spacing: SwitcherLayout.spacing),
            count: SwitcherLayout.columns(for: model.items.count)
        )
        LazyVGrid(columns: columns, alignment: .leading, spacing: SwitcherLayout.spacing) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                SwitcherTile(item: item, thumbnail: model.thumbnails[item.id], isSelected: index == model.selection)
                    .onTapGesture { model.onPick?(index) }
            }
        }
        .padding(SwitcherLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SwitcherTile: View {
    let item: SwitcherItem
    let thumbnail: NSImage?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 124, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        AppIconView(icon: item.icon, size: 26).offset(x: 6, y: 6)
                    }
                    .frame(height: 101)
            } else {
                AppIconView(icon: item.icon, size: 48)
                Minimap(rect: item.minimap, isMinimized: item.isMinimized)
                    .frame(width: 72, height: 45)
            }

            VStack(spacing: 2) {
                Text(verbatim: item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: item.isMinimized ? L("Minimized") : item.appName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(width: SwitcherLayout.tileWidth, height: SwitcherLayout.tileHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// The window's outline drawn at its position on its display. Lets you tell apart
/// several windows of the same app without Screen Recording permission.
struct Minimap: View {
    let rect: CGRect?
    let isMinimized: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                if let rect {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.accentColor.opacity(isMinimized ? 0 : 0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 1)
                        )
                        .frame(
                            width: max(4, rect.width * geo.size.width),
                            height: max(3, rect.height * geo.size.height)
                        )
                        .offset(x: rect.minX * geo.size.width, y: rect.minY * geo.size.height)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct AppIconView: View {
    let icon: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(Color.secondary.opacity(0.3))
            }
        }
        .frame(width: size, height: size)
    }
}
