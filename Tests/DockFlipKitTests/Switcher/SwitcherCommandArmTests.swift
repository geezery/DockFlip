import Testing
@testable import DockFlipKit

@Suite("SwitcherCommandArm")
struct SwitcherCommandArmTests {
    @Test func openingWithCommandHeldArms() {
        var arm = SwitcherCommandArm()
        arm.open(commandHeld: true)
        let switches = arm.released()
        #expect(switches)
    }

    @Test func openingWithCommandUpDoesNotArm() {
        var arm = SwitcherCommandArm()
        arm.open(commandHeld: false)
        let switches = arm.released()
        #expect(!switches)
    }

    @Test func oneReleaseDisarms() {
        // ⇧, ⌃ and ⌥ changes and late copies also arrive as releases.
        var arm = SwitcherCommandArm()
        arm.open(commandHeld: true)
        let first = arm.released()
        let second = arm.released()
        #expect(first)
        #expect(!second)
        #expect(!arm.isArmed)
    }

    @Test func pressingCommandAgainReArms() {
        // Let go of ⌘ to filter, clear the filter, hold ⌘ again and let go.
        var arm = SwitcherCommandArm()
        arm.open(commandHeld: true)
        _ = arm.released()
        arm.pressed(commandHeld: true)
        let switches = arm.released()
        #expect(switches)
    }

    @Test func stalePressDoesNotReArm() {
        // A late copy of the press arrives after ⌘ is already up.
        var arm = SwitcherCommandArm()
        arm.open(commandHeld: true)
        _ = arm.released()
        arm.pressed(commandHeld: false)
        let switches = arm.released()
        #expect(!switches)
    }

    @Test func stalePressKeepsAnArmedState() {
        var arm = SwitcherCommandArm()
        arm.open(commandHeld: true)
        arm.pressed(commandHeld: false)
        #expect(arm.isArmed)
    }

    @Test func resetDisarms() {
        var arm = SwitcherCommandArm()
        arm.open(commandHeld: true)
        arm.reset()
        let switches = arm.released()
        #expect(!switches)
    }
}
