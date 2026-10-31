import SwiftUI

/// What the switcher's panel hosts: the Flip 3D stack or the Windows 11 grid,
/// whichever `SwitcherModel.style` names. The controller sets the style as the
/// switcher opens, so a change in Settings shows from the next ⌘Tab.
struct SwitcherRootView: View {
    @ObservedObject var model: SwitcherModel

    var body: some View {
        switch model.style {
        case .flip3D:
            SwitcherView(model: model)
        case .grid:
            SwitcherGridView(model: model)
        }
    }
}
