import AppKit

/// "Tell a Friend…" and "Buy DockFlip a Coffee…" in the menu bar menu. Both hand
/// off to macOS: the share sheet sends the message, the browser opens the page.
/// DockFlip itself still has no networking code.
@MainActor
enum Sharing {
    static let homepage = URL(string: "https://geezery.github.io/DockFlip/")!
    static let coffee = URL(string: "https://github.com/sponsors/geezery?frequency=one-time")!

    /// The macOS share sheet (Messages, Mail, AirDrop…), under the menu bar icon.
    static func tellAFriend(from button: NSStatusBarButton?) {
        let text = L("DockFlip brings the best bits of Windows to the Mac: window lists in the Dock, a Flip 3D ⌘Tab that switches windows, and snapping. Free and open source.")
        let picker = NSSharingServicePicker(items: [text, homepage])
        // A share sheet the user asked for: the one place DockFlip comes forward.
        NSApp.activate()
        if let button {
            picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        } else {
            NSWorkspace.shared.open(homepage)
        }
    }

    static func buyACoffee() {
        NSWorkspace.shared.open(coffee)
    }
}
