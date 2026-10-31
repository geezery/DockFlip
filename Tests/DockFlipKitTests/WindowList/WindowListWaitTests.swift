import Testing
@testable import DockFlipKit

/// An app's windows are read off the main thread, so a slow app's windows can
/// arrive after the 250 ms hover delay: its list then opens when they arrive,
/// as long as the mouse is still on its icon.
@Suite("WindowListWait: a list whose windows arrive late")
struct WindowListWaitTests {
    let chrome = "com.google.Chrome"

    @Test func windowsArrivingLateOpenTheList() {
        var wait = WindowListWait()
        // The hover delay ran out before Chrome answered.
        wait.nothingToList(chrome)
        // Another app's window changed: Chrome still has none, nothing opens.
        #expect(wait.keyToOpen(isVisible: false) { _ in false } == nil)
        // Chrome's windows arrive.
        #expect(wait.keyToOpen(isVisible: false) { $0 == chrome } == chrome)
    }

    @Test func nothingOpensAfterTheMouseLeft() {
        var wait = WindowListWait()
        wait.nothingToList(chrome)
        wait.stop() // the mouse left the icon, or moved to another one
        #expect(wait.key == nil)
        #expect(wait.keyToOpen(isVisible: false) { _ in true } == nil)
    }

    @Test func nothingOpensAfterAPressOnTheIcon() {
        var wait = WindowListWait()
        wait.nothingToList(chrome)
        // A click reopens the app: its new window must not pop a list up under the mouse.
        wait.stop()
        #expect(wait.keyToOpen(isVisible: false) { $0 == chrome } == nil)
    }

    @Test func anOpenListIsLeftToRedrawItself() {
        var wait = WindowListWait()
        wait.nothingToList(chrome)
        #expect(wait.keyToOpen(isVisible: true) { _ in true } == nil)
    }

    @Test func nothingWaitsUntilAListFoundNothing() {
        let wait = WindowListWait()
        #expect(wait.key == nil)
        #expect(wait.keyToOpen(isVisible: false) { _ in true } == nil)
    }

    @Test func theLatestIconWaits() {
        var wait = WindowListWait()
        wait.nothingToList(chrome)
        wait.nothingToList("com.microsoft.Word")
        #expect(wait.keyToOpen(isVisible: false) { _ in true } == "com.microsoft.Word")
    }
}
