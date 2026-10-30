import AppKit
import Testing
@testable import DockFlipKit

@Suite("WindowRegistry frames")
@MainActor
struct WindowRegistryFrameTests {
    private func window(_ id: CGWindowID, frame: CGRect, minimized: Bool = false) -> WindowSnapshot {
        WindowSnapshot(
            id: id, pid: 42, bundleID: "com.apple.TextEdit", appName: "TextEdit", icon: nil,
            title: "", frame: frame, isMinimized: minimized, isAppHidden: false
        )
    }

    @Test func knownFrameAnswersFromMemory() {
        // Snapping reads this on every key press and drag event: memory only, no Accessibility.
        let registry = WindowRegistry()
        let frame = CGRect(x: 0, y: 25, width: 900, height: 700)
        registry.windows[7] = window(7, frame: frame)
        #expect(registry.knownFrame(of: 7) == frame)
        #expect(registry.knownFrame(of: 8) == nil)
    }

    @Test func noKnownFrameForAMinimizedOrNeverReadWindow() {
        let registry = WindowRegistry()
        registry.windows[7] = window(7, frame: CGRect(x: 0, y: 25, width: 900, height: 700), minimized: true)
        registry.windows[8] = window(8, frame: .zero)
        #expect(registry.knownFrame(of: 7) == nil)
        #expect(registry.knownFrame(of: 8) == nil)
    }

    @Test func aFrameReadOffTheMainThreadIsKept() {
        // After a snap the app's answer updates memory, so a second key press sees the new frame.
        let registry = WindowRegistry()
        registry.windows[7] = window(7, frame: CGRect(x: 0, y: 25, width: 900, height: 700))
        let snapped = CGRect(x: 0, y: 25, width: 720, height: 875)
        registry.remember(snapped, of: 7)
        #expect(registry.knownFrame(of: 7) == snapped)
        // A window closed meanwhile is not brought back.
        registry.remember(snapped, of: 8)
        #expect(registry.window(8) == nil)
    }
}
