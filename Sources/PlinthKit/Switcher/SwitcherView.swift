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
    /// Document file name, when the app reports one.
    let document: String?
    /// Name of the display the window is on, e.g. "Built-in Retina Display".
    let screenName: String?
    /// "1440 × 900"
    let sizeText: String
    /// The app's colour, taken from its icon; tints the card's title bar.
    let tint: Color
}

@MainActor
final class SwitcherModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var selection = 0
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    var onPick: ((Int) -> Void)?
    var onCancel: (() -> Void)?

    /// 0 for the card in front, 1 for the one behind it, and so on (wrapping).
    func depth(of index: Int) -> Int {
        guard !items.isEmpty else { return 0 }
        return ((index - selection) % items.count + items.count) % items.count
    }
}

/// The ⌘Tab switcher, in the style of Windows 7 Flip 3D: windows stand in a
/// slanted stack, the selected one in front at the lower right, the others
/// receding to the upper left in perspective. Each ⌘Tab throws the front window
/// to the back of the stack; releasing ⌘ opens the window in front.
struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    /// Cards further back than this fade out.
    private let visibleDepth = 7

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width * 0.42, 760)
            let cardHeight = cardWidth * 0.62

            ZStack {
                // The desktop stays visible behind the stack, slightly dimmed.
                Color.black.opacity(0.28)
                    .contentShape(Rectangle())
                    .onTapGesture { model.onCancel?() }

                ZStack {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        let depth = model.depth(of: index)
                        FanCard(item: item, thumbnail: model.thumbnails[item.id], isFront: depth == 0)
                            .frame(width: cardWidth, height: cardHeight)
                            // Every window turned the same way: its left edge further away.
                            .rotation3DEffect(
                                .degrees(-24),
                                axis: (x: 0, y: 1, z: 0),
                                anchor: .center,
                                perspective: 0.5
                            )
                            .scaleEffect(max(0.5, 1 - Double(depth) * 0.06))
                            // Receding up and to the left.
                            .offset(x: CGFloat(depth) * -cardWidth * 0.17, y: CGFloat(depth) * -cardHeight * 0.11)
                            .opacity(depth > visibleDepth ? 0 : 1 - Double(depth) * 0.06)
                            .zIndex(Double(1000 - depth))
                            .onTapGesture { model.onPick?(index) }
                    }
                }
                // The front window sits right of and below the centre.
                .offset(x: cardWidth * 0.32, y: cardHeight * 0.22)
                .animation(.spring(response: 0.42, dampingFraction: 0.80), value: model.selection)

                VStack {
                    Spacer()
                    if model.items.indices.contains(model.selection) {
                        let front = model.items[model.selection]
                        HStack(spacing: 12) {
                            AppIconView(icon: front.icon, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: front.title)
                                    .font(.system(size: 17, weight: .semibold))
                                    .lineLimit(1)
                                Text(verbatim: front.isMinimized ? "\(front.appName) · \(L("Minimized"))" : front.appName)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .animation(nil, value: model.selection)
                    }
                }
                .padding(.bottom, geo.size.height * 0.08)
            }
        }
    }
}

/// One window in the stack: its live thumbnail when previews are on. Without
/// previews, a card that still tells windows apart: the title in a title bar
/// tinted with the app's colour, the document name, the display, the size, and a
/// mini-map of where the window sits on screen.
struct FanCard: View {
    let item: SwitcherItem
    let thumbnail: NSImage?
    let isFront: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 11, height: 11)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 11, height: 11)
                Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 11, height: 11)
                Text(verbatim: item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 44)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(item.tint.opacity(0.22))
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1) }

            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    details
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isFront ? Color.accentColor : Color.white.opacity(0.22), lineWidth: isFront ? 3 : 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 26, y: 14)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.appName): \(item.title)"))
        .accessibilityAddTraits(isFront ? [.isButton, .isSelected] : [.isButton])
    }

    private var details: some View {
        HStack(alignment: .center, spacing: 28) {
            AppIconView(icon: item.icon, size: 116)
                .opacity(item.isMinimized ? 0.6 : 1)
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: item.title)
                    .font(.system(size: 22, weight: .semibold))
                    .lineLimit(3)
                if let document = item.document, document != item.title {
                    Label {
                        Text(verbatim: document).lineLimit(1)
                    } icon: {
                        Image(systemName: "doc")
                    }
                    .font(.system(size: 14))
                }
                Text(verbatim: item.isMinimized ? "\(item.appName) · \(L("Minimized"))" : item.appName)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Minimap(rect: item.minimap, isMinimized: item.isMinimized)
                        .frame(width: 144, height: 90)
                    VStack(alignment: .leading, spacing: 4) {
                        if let screen = item.screenName {
                            Text(verbatim: screen).lineLimit(2)
                        }
                        Text(verbatim: item.sizeText)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
