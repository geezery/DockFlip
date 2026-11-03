import SwiftUI

/// The Flip 3D | Grid switch at the bottom of the open switcher, so the look can be
/// changed where it is seen instead of in Settings. It sits in the same place in both
/// looks, so a second click on the same spot goes back. A click changes the look at
/// once and keeps the switcher open; the controller saves it as the Settings choice.
/// Hidden when the organization's profile sets the look (`SwitcherModel.canChangeStyle`).
struct SwitcherStyleToggle: View {
    @ObservedObject var model: SwitcherModel

    var body: some View {
        HStack(spacing: 2) {
            segment(.flip3D, symbol: "square.stack.3d.down.right", label: Text("Flip 3D"))
            segment(.grid, symbol: "square.grid.2x2", label: Text("Grid"))
        }
        .padding(3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        // Clicks between the segments must not fall through to cancel.
        .contentShape(Capsule())
        .onTapGesture {}
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("⌘Tab switcher"))
    }

    private func segment(_ style: SwitcherStyle, symbol: String, label: Text) -> some View {
        let isOn = model.style == style
        return HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            label
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(isOn ? Color.primary : Color.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(isOn ? 0.14 : 0), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { model.onChangeStyle?(style) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
    }
}
