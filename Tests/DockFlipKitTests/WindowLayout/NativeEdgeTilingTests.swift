import Testing
@testable import DockFlipKit

@Suite("NativeEdgeTiling")
struct NativeEdgeTilingTests {
    private func isOn(_ values: [String: Bool]) -> Bool {
        NativeEdgeTiling.isOn(reading: { values[$0] })
    }

    @Test func neverWrittenMeansOn() {
        #expect(isOn([:]))
    }

    @Test func offOnlyWhenEveryKeyIsOff() {
        #expect(!isOn(["EnableTilingByEdgeDrag": false, "EnableTopTilingByEdgeDrag": false]))
        #expect(isOn(["EnableTilingByEdgeDrag": false, "EnableTopTilingByEdgeDrag": true]))
        #expect(isOn(["EnableTilingByEdgeDrag": true, "EnableTopTilingByEdgeDrag": false]))
    }

    @Test func oneKeyLeftAtItsDefaultIsOn() {
        // Turning off one switch in System Settings writes only its own key.
        #expect(isOn(["EnableTilingByEdgeDrag": false]))
        #expect(isOn(["EnableTopTilingByEdgeDrag": false]))
    }

    @Test func turnOffCoversEveryKeyTheRuleReads() {
        let allOff = Dictionary(uniqueKeysWithValues: NativeEdgeTiling.keys.map { ($0, false) })
        #expect(!isOn(allOff))
    }
}
