import ApplicationServices
import Testing
@testable import DockFlipKit

@Suite("FrameSetter")
struct FrameSetterTests {
    private let rect = CGRect(x: 10, y: 20, width: 800, height: 600)

    @Test func setsSizeThenPositionThenSizeAgain() {
        // Some apps clamp the size against the old position, so the size is set twice.
        var calls: [FrameSetter.Attribute] = []
        let error = FrameSetter.apply(rect) { attribute, asked in
            #expect(asked == rect)
            calls.append(attribute)
            return .success
        }
        #expect(calls == [.size, .position, .size])
        #expect(error == .success)
    }

    @Test func aHungAppIsAskedOnce() {
        // Each call to a hung app waits the 1 s timeout: after the first, the rest are not made.
        var calls = 0
        let error = FrameSetter.apply(rect) { _, _ in
            calls += 1
            return .cannotComplete
        }
        #expect(calls == 1)
        #expect(error == .cannotComplete)
    }

    @Test func aRefusedCallDoesNotStopTheRest() {
        // A fixed-size window refuses its size but still moves.
        var calls: [FrameSetter.Attribute] = []
        let error = FrameSetter.apply(rect) { attribute, _ in
            calls.append(attribute)
            return attribute == .size ? .attributeUnsupported : .success
        }
        #expect(calls == [.size, .position, .size])
        #expect(error == .attributeUnsupported)
    }
}
