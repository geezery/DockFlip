import SwiftUI

/// The frosted glass behind DockFlip's panels (the ⌘Tab grid, the Dock list,
/// Snap Assist, the pills), with one Dark Mode fix: there the system materials
/// come out about as dark as the dark windows behind them, so a panel melts into
/// the desktop. A light wash lifts it to the grey of Windows 11's own dark
/// panels. Light Mode gets the material as it is.
struct FrostedFill<S: Shape>: View {
    var material: Material = .regularMaterial
    let shape: S
    // Not private: a private stored property would make the memberwise init private.
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            shape.fill(material)
            if colorScheme == .dark {
                shape.fill(Color.white.opacity(0.09))
            }
        }
    }
}

extension View {
    /// `.background(material, in: shape)`, lifted off dark windows in Dark Mode (`FrostedFill`).
    func frostedBackground<S: Shape>(_ material: Material = .regularMaterial, in shape: S) -> some View {
        background(FrostedFill(material: material, shape: shape))
    }
}

/// The hairline round a frosted panel. A white line vanishes on light glass and a
/// faint one on dark glass, so each appearance gets its own: brighter on dark,
/// a dark hairline on light.
struct FrostedEdge<S: InsettableShape>: View {
    let shape: S
    // Not private: a private stored property would make the memberwise init private.
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        shape.strokeBorder(
            colorScheme == .dark ? Color.white.opacity(0.26) : Color.black.opacity(0.12),
            lineWidth: 1
        )
    }
}

extension View {
    /// A frosted panel's background and edge in one (`FrostedFill`, `FrostedEdge`).
    func frostedPanel<S: InsettableShape>(_ material: Material = .regularMaterial, in shape: S) -> some View {
        frostedBackground(material, in: shape).overlay(FrostedEdge(shape: shape))
    }
}
