import SwiftUI

/// What the switcher's panel hosts: the Flip 3D stack or the Windows 11 grid,
/// whichever `SwitcherModel.style` names, with the toggle between the two at the
/// bottom of the screen (`SwitcherStyleToggle`). The controller sets the style as
/// the switcher opens, and again when the toggle is clicked.
struct SwitcherRootView: View {
    @ObservedObject var model: SwitcherModel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                switch model.style {
                case .flip3D:
                    SwitcherView(model: model)
                case .grid:
                    SwitcherGridView(model: model)
                }
                if model.canChangeStyle {
                    SwitcherStyleToggle(model: model)
                        .padding(.bottom, geo.size.height * 0.025)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
