import AppKit
import ApplicationServices

/// A window's state as its app reported it. Nil where the app did not say.
struct WindowAttributes {
    var title: String?
    var frame: CGRect?
    var isMinimized: Bool?
    /// File name of the document shown in the window.
    var document: String?
}

/// One read of an app's windows from Accessibility: its window list, and each
/// window's kind and state.
///
/// It runs on the app's own queue (`AppQueues`), never on the main thread: a hung
/// app answers each call only after the 1 s timeout, and on the main thread every
/// click and key press on the Mac would wait with it. The main actor then
/// reconciles the model with the result (`WindowsReconcile`).
/// Accessibility elements are safe to send between threads (`SendableElement`).
struct WindowsRead: @unchecked Sendable {
    struct Window: @unchecked Sendable {
        let id: CGWindowID
        let element: AXUIElement
        /// Whether it is a standard window; nil when its role did not arrive in time.
        let isStandard: Bool?
        let attributes: WindowAttributes
    }

    /// The answer to the window list: `.cannotComplete` when the app did not answer in time.
    var error: AXError
    var windows: [Window]

    /// Reads the app's windows. Blocks as long as the app takes to answer: call it
    /// on the app's queue only.
    static func read(app: AXUIElement) -> WindowsRead {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard error != .cannotComplete else { return WindowsRead(error: error, windows: []) }
        var windows: [Window] = []
        var hung = false
        for element in (value as? [AXUIElement]) ?? [] {
            guard let id = element.windowID else { continue }
            // One window's read timed out: the app is hung, and every further call
            // would wait as long. The rest count as not answered, to be read again.
            guard !hung else {
                windows.append(Window(id: id, element: element, isStandard: nil, attributes: WindowAttributes()))
                continue
            }
            let (window, timedOut) = Window.read(id: id, element: element)
            hung = timedOut
            windows.append(window)
        }
        return WindowsRead(error: error, windows: windows)
    }
}

extension WindowsRead.Window {
    private static let names = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXPositionAttribute,
        kAXSizeAttribute, kAXMinimizedAttribute, kAXDocumentAttribute
    ]

    /// Reads one window's kind and state, in one round trip to the app.
    /// Blocks as long as the app takes to answer: never call it on the main thread.
    static func read(id: CGWindowID, element: AXUIElement) -> (window: Self, timedOut: Bool) {
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values)
        if error == .cannotComplete {
            return (Self(id: id, element: element, isStandard: nil, attributes: WindowAttributes()), true)
        }
        guard error == .success, let array = values as? [AnyObject], array.count == names.count else {
            return (readOneByOne(id: id, element: element), false)
        }
        // A missing attribute comes back as an AXValue holding its error, so each
        // value is cast to the type expected.
        let window = Self(
            id: id,
            element: element,
            isStandard: isStandard(role: array[0] as? String, subrole: array[1] as? String),
            attributes: WindowAttributes(
                title: array[2] as? String,
                frame: frame(position: array[3], size: array[4]),
                isMinimized: array[5] as? Bool,
                document: (array[6] as? String).flatMap(documentName)
            )
        )
        return (window, false)
    }

    /// For an app that does not answer several attributes at once.
    private static func readOneByOne(id: CGWindowID, element: AXUIElement) -> Self {
        Self(
            id: id,
            element: element,
            isStandard: isStandard(role: element.string(kAXRoleAttribute), subrole: element.string(kAXSubroleAttribute)),
            attributes: WindowAttributes(
                title: element.string(kAXTitleAttribute),
                frame: element.frame,
                isMinimized: element.bool(kAXMinimizedAttribute),
                document: element.string(kAXDocumentAttribute).flatMap(documentName)
            )
        )
    }

    /// A failed read is not an answer: nil when the role, or a window's subrole,
    /// did not arrive, so the window is kept if known and read again.
    private static func isStandard(role: String?, subrole: String?) -> Bool? {
        guard let role else { return nil }
        guard role == kAXWindowRole else { return false }
        guard let subrole else { return nil }
        return subrole == kAXStandardWindowSubrole
    }

    private static func frame(position: AnyObject, size: AnyObject) -> CGRect? {
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    /// "file:///Users/x/Budget%202026.xlsx" → "Budget 2026.xlsx"
    private static func documentName(_ value: String) -> String? {
        let url = URL(string: value) ?? URL(fileURLWithPath: value)
        let name = url.lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
