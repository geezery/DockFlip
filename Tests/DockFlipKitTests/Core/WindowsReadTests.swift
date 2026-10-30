import ApplicationServices
import Testing
@testable import DockFlipKit

@Suite("WindowsRead")
struct WindowsReadTests {
    @Test func aStandardWindowIsListed() {
        #expect(WindowsRead.Window.isStandard(role: kAXWindowRole, subrole: kAXStandardWindowSubrole) == true)
    }

    @Test func panelsAndOtherRolesAreNotWindowsToList() {
        #expect(WindowsRead.Window.isStandard(role: kAXWindowRole, subrole: kAXFloatingWindowSubrole) == false)
        #expect(WindowsRead.Window.isStandard(role: kAXSheetRole, subrole: nil) == false)
    }

    @Test func aRoleThatDidNotArriveIsNoAnswer() {
        // A failed read is not an answer: neither "a window" nor "not a window".
        #expect(WindowsRead.Window.isStandard(role: nil, subrole: nil) == nil)
        #expect(WindowsRead.Window.isStandard(role: kAXWindowRole, subrole: nil) == nil)
    }
}
