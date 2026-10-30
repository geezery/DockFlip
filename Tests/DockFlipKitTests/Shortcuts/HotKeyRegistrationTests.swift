import Testing
@testable import DockFlipKit

@Suite("HotKeyRegistration")
struct HotKeyRegistrationTests {
    private let commandTab = HotkeyCommand.switcher(.commandTab(shift: false))
    private let commandShiftTab = HotkeyCommand.switcher(.commandTab(shift: true))

    private func registration(_ results: [(HotkeyCommand, Bool)]) -> HotKeyRegistration {
        var registration = HotKeyRegistration()
        for (command, ok) in results { registration.record(command, registered: ok) }
        return registration
    }

    @Test func bothCommandTabBindingsOwnCommandTab() {
        let all = registration([(commandTab, true), (commandShiftTab, true), (.snap(.left), true)])
        #expect(all.ownsCommandTab)
        #expect(all.commandTabToRelease.isEmpty)
        #expect(all.failed.isEmpty)
    }

    @Test func nothingRegisteredOwnsNothing() {
        #expect(!HotKeyRegistration().ownsCommandTab)
    }

    @Test func anotherAppHoldingCommandTabIsNotHiddenByTheOtherShortcuts() {
        // AltTab holds ⌘Tab and ⌘⇧Tab; every ⌃⌥ shortcut still registers.
        let held = registration([(commandTab, false), (commandShiftTab, false), (.snap(.left), true), (.showDesktop, true)])
        #expect(!held.ownsCommandTab)
        #expect(held.failed == [commandTab, commandShiftTab])
        #expect(held.registered == [.snap(.left), .showDesktop])
        #expect(held.commandTabToRelease.isEmpty)
    }

    @Test func halfOfCommandTabIsLetGo() {
        var half = registration([(commandTab, true), (commandShiftTab, false), (.showDesktop, true)])
        #expect(!half.ownsCommandTab)
        #expect(half.commandTabToRelease == [commandTab])
        half.release(commandTab)
        #expect(half.registered == [.showDesktop])
        #expect(half.commandTabToRelease.isEmpty)
        #expect(!half.ownsCommandTab)

        let otherHalf = registration([(commandTab, false), (commandShiftTab, true)])
        #expect(otherHalf.commandTabToRelease == [commandShiftTab])
    }

    @Test func failedShortcutsAreNamedAsTyped() {
        #expect(commandTab.shortcutName == "⌘Tab")
        #expect(commandShiftTab.shortcutName == "⌘⇧Tab")
        #expect(HotkeyCommand.snap(.left).shortcutName == "⌃⌥←")
        #expect(HotkeyCommand.moveToDisplay(.right).shortcutName == "⌃⌥⇧→")
        #expect(HotkeyCommand.dockItem(0).shortcutName == "⌃⌥1")
        #expect(HotkeyCommand.showDesktop.shortcutName == "⌃⌥D")
    }
}
