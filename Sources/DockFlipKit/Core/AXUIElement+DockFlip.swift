import AppKit
import ApplicationServices

/// Private but long-stable API used by every macOS window manager to map an
/// Accessibility window element to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Private API (used by AltTab): an Accessibility element from a remote token —
/// pid (4 bytes), 0 (4), 0x636f636f "coco" (4), element id (8). The only way to
/// reach windows an app leaves out of `kAXWindowsAttribute`: windows on other
/// Spaces, including full-screen windows.
@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

extension AXUIElement {
    func copyAttribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value
    }

    /// Several attributes in one round trip to the app, in the order asked, or
    /// nil if the call failed. A missing attribute comes back as an AXValue
    /// holding its error, so cast each value to the type expected.
    func copyAttributes(_ names: [String]) -> [AnyObject]? {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(self, names as CFArray, [], &values) == .success,
              let array = values as? [AnyObject], array.count == names.count else { return nil }
        return array
    }

    func string(_ name: String) -> String? {
        copyAttribute(name) as? String
    }

    func bool(_ name: String) -> Bool? {
        copyAttribute(name) as? Bool
    }

    func element(_ name: String) -> AXUIElement? {
        guard let value = copyAttribute(name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func elements(_ name: String) -> [AXUIElement] {
        (copyAttribute(name) as? [AXUIElement]) ?? []
    }

    /// The one decoder of a position and a size AXValue into a frame, for a
    /// frame read alone (`frame`) or in a batch (`copyAttributes`). Nil when
    /// either is missing, not an AXValue (a batch's missing attribute is an
    /// error AXValue), or not the point or size asked for.
    static func frame(position: CFTypeRef?, size: CFTypeRef?) -> CGRect? {
        guard let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    /// Frame in global coordinates with the origin at the top-left of the primary display.
    var frame: CGRect? {
        Self.frame(position: copyAttribute(kAXPositionAttribute), size: copyAttribute(kAXSizeAttribute))
    }

    /// The window's id. Every answer also goes to the self-check: on a window
    /// this private call should always work, and a macOS where it stops working
    /// shows DockFlip no windows at all.
    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        let status = _AXUIElementGetWindow(self, &id)
        let worked = status == .success && id != 0
        SelfCheck.record { $0.windowIDs.record(worked, error: status.rawValue) }
        return worked ? id : nil
    }

    /// `windowID` kept out of the self-check, for elements that need not be
    /// windows (the search for windows on other Spaces tries every element id)
    /// or may be gone (a window's destroyed notification).
    var windowIDOfAnyElement: CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(self, &id) == .success, id != 0 else { return nil }
        return id
    }

    @discardableResult
    func set(_ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, name as CFString, value) == .success
    }

    @discardableResult
    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(self, action as CFString) == .success
    }
}

/// An Accessibility element handed between the main thread and a background
/// task. Accessibility calls are thread-safe, so this is safe to send.
struct SendableElement: @unchecked Sendable {
    let element: AXUIElement
}
