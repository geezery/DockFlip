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
    /// On another desktop or full screen.
    let isOnOtherSpace: Bool
    /// Document file name, when the app reports one.
    let document: String?
    /// Name of the display the window is on, e.g. "Built-in Retina Display".
    let screenName: String?
    /// "1440 × 900"
    let sizeText: String
    /// The app's colour, taken from its icon; tints the card's title bar.
    let tint: Color
}

extension SwitcherItem {
    /// "Safari", "Safari · Minimized", "Safari · On another desktop".
    var subtitle: String {
        if isMinimized { return "\(appName) · \(L("Minimized"))" }
        if isOnOtherSpace { return "\(appName) · \(L("On another desktop"))" }
        return appName
    }
}

@MainActor
final class SwitcherModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var selection = 0
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    /// Typed filter text; empty when not filtering.
    @Published var query = ""
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
                    if !model.query.isEmpty {
                        SearchPill(query: model.query, count: model.items.count)
                            .padding(.top, geo.size.height * 0.07)
                    }
                    Spacer()
                    if model.items.isEmpty && !model.query.isEmpty {
                        Text("No windows match")
                            .font(.system(size: 17, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.regularMaterial, in: Capsule())
                    } else if model.items.indices.contains(model.selection) {
                        let front = model.items[model.selection]
                        HStack(spacing: 12) {
                            AppIconView(icon: front.icon, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: front.title)
                                    .font(.system(size: 17, weight: .semibold))
                                    .lineLimit(1)
                                Text(verbatim: front.subtitle)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .animation(nil, value: model.selection)
                    }
                    if model.query.isEmpty {
                        Text("Type to filter")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, geo.size.height * 0.08)
            }
        }
    }
}

/// The typed filter, at the top of the screen while filtering.
struct SearchPill: View {
    let query: String
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: query)
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(1)
            Text(verbatim: "\(count)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.1), in: Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
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
                if thumbnail == nil {
                    // A faint wash of the app's colour, so cards of different apps differ at a glance.
                    LinearGradient(colors: [item.tint.opacity(0.16), item.tint.opacity(0.03)], startPoint: .top, endPoint: .bottom)
                }
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
                Text(verbatim: item.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Minimap(rect: item.minimap, isMinimized: item.isMinimized, tint: item.tint, icon: item.icon)
                        .frame(width: 160, height: 100)
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

/// A miniature of the window's display with the window drawn where it is, in
/// the app's colour, with a title bar and the app's icon. Tells apart several
/// windows of the same app without Screen Recording permission.
struct Minimap: View {
    let rect: CGRect?
    let isMinimized: Bool
    var tint: Color = .accentColor
    var icon: NSImage? = nil

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let screenRadius = max(2, min(size.width, size.height) * 0.07)
            ZStack(alignment: .topLeading) {
                // The display: a dim wallpaper in the app's colour, with a menu bar.
                RoundedRectangle(cornerRadius: screenRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [tint.opacity(0.30), Color.black.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: max(1.5, size.height * 0.05))
                RoundedRectangle(cornerRadius: screenRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)

                if let rect {
                    let frame = CGRect(
                        x: rect.minX * size.width,
                        y: rect.minY * size.height,
                        width: max(5, rect.width * size.width),
                        height: max(4, rect.height * size.height)
                    )
                    MiniWindow(size: frame.size, tint: tint, icon: icon, isMinimized: isMinimized)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: screenRadius, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}

/// One window inside the mini-map.
private struct MiniWindow: View {
    let size: CGSize
    let tint: Color
    let icon: NSImage?
    let isMinimized: Bool

    var body: some View {
        let radius = max(1.5, min(size.width, size.height) * 0.06)
        let barHeight = max(2, min(size.height * 0.16, 14))
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let iconSize = min(size.width, size.height - barHeight) * 0.5

        ZStack(alignment: .top) {
            if isMinimized {
                // Minimized: only a dashed outline where the window would be.
                shape.fill(tint.opacity(0.12))
                shape.strokeBorder(tint, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            } else {
                shape.fill(tint)
                // Light from above, like a window's surface.
                shape.fill(LinearGradient(
                    colors: [Color.white.opacity(0.30), Color.white.opacity(0), Color.black.opacity(0.18)],
                    startPoint: .top, endPoint: .bottom
                ))
                // Title bar with traffic lights, when there is room for them.
                HStack(spacing: max(1, barHeight * 0.22)) {
                    if size.width > 40 {
                        let dot = max(2, barHeight * 0.42)
                        Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: dot, height: dot)
                        Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: dot, height: dot)
                        Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: dot, height: dot)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, max(1.5, barHeight * 0.35))
                .frame(height: barHeight)
                .background(Color.black.opacity(0.22))
                shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 0.75)
            }
            if let icon, iconSize >= 12 {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: min(iconSize, 48), height: min(iconSize, 48))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .opacity(isMinimized ? 0.6 : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, barHeight)
            }
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(isMinimized ? 0 : 0.4), radius: 3, y: 1.5)
    }
}
