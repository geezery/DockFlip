import AppKit
import Testing
@testable import DockFlipKit

@Suite("WindowRegistry")
@MainActor
struct WindowRegistryTests {
    @Test func hasWindowsAnswersFromWhatIsTracked() {
        // The Dock click tap asks this for every press on an icon: memory only, no Accessibility.
        let registry = WindowRegistry()
        #expect(!registry.hasWindows(bundleID: "com.apple.Safari"))
        registry.windows[7] = WindowSnapshot(
            id: 7, pid: 42, bundleID: "com.apple.Safari", appName: "Safari", icon: nil,
            title: "", frame: .zero, isMinimized: true, isAppHidden: false
        )
        #expect(registry.hasWindows(bundleID: "com.apple.Safari"))
        #expect(!registry.hasWindows(bundleID: "com.apple.mail"))
    }
}
