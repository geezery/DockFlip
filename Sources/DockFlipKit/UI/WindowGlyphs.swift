import AppKit
import SwiftUI

// Small views shared by the ⌘Tab switcher and the Dock window list: an app
// icon, and the mini-map that tells windows apart without screenshots.

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
