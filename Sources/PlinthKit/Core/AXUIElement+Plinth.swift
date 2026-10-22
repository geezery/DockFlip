import AppKit
import ApplicationServices

/// Private but long-stable API used by every macOS window manager to map an
/// Accessibility window element to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    func copyAttribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value
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

    private func axValue<T>(_ name: String, type: AXValueType, initial: T) -> T? {
        guard let value = copyAttribute(name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = initial
        return AXValueGetValue(value as! AXValue, type, &result) ? result : nil
    }

    /// Frame in global coordinates with the origin at the top-left of the primary display.
    var frame: CGRect? {
        guard let origin = axValue(kAXPositionAttribute, type: .cgPoint, initial: CGPoint.zero),
              let size = axValue(kAXSizeAttribute, type: .cgSize, initial: CGSize.zero) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(self, &id) == .success, id != 0 else { return nil }
        return id
    }

    var isStandardWindow: Bool {
        string(kAXRoleAttribute) == kAXWindowRole && string(kAXSubroleAttribute) == kAXStandardWindowSubrole
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
