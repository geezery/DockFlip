import ApplicationServices

/// Moves and resizes a window through Accessibility: size, position, size again,
/// because some apps clamp the size against the old position.
///
/// It waits on the app, so `WindowRegistry` runs it on the app's queue
/// (`AppQueues`), never on the main thread.
enum FrameSetter {
    enum Attribute: Equatable {
        case size
        case position
    }

    /// What the app answered: the error of the last call made, and the frame it
    /// reports afterwards (nil when it did not answer).
    struct Answer: Sendable {
        let error: AXError
        let frame: CGRect?
    }

    /// The calls, in order, through `set`. A hung app answers each call only
    /// after the messaging timeout, so after one timeout the rest are not asked.
    static func apply(_ rect: CGRect, set: (Attribute, CGRect) -> AXError) -> AXError {
        var error = AXError.success
        for attribute in [Attribute.size, .position, .size] {
            error = set(attribute, rect)
            if error == .cannotComplete { break }
        }
        return error
    }

    /// Sets `rect` on the window `element` and reads back where it ended up.
    static func set(_ rect: CGRect, on element: AXUIElement) -> Answer {
        let error = apply(rect) { attribute, rect in
            var size = rect.size
            var origin = rect.origin
            let name: String
            let value: AXValue?
            switch attribute {
            case .size:
                name = kAXSizeAttribute
                value = AXValueCreate(.cgSize, &size)
            case .position:
                name = kAXPositionAttribute
                value = AXValueCreate(.cgPoint, &origin)
            }
            guard let value else { return .failure }
            return AXUIElementSetAttributeValue(element, name as CFString, value)
        }
        return Answer(error: error, frame: error == .cannotComplete ? nil : element.frame)
    }
}
