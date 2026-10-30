import Testing
@testable import DockFlipKit

@Suite("MRUList")
struct MRUListTests {
    @Test func initRemovesDuplicates() {
        #expect(MRUList([1, 2, 1, 3]).items == [1, 2, 3])
    }

    @Test func moveToFront() {
        var list = MRUList([1, 2, 3])
        list.moveToFront(3)
        #expect(list.items == [3, 1, 2])
        list.moveToFront(4)
        #expect(list.items == [4, 3, 1, 2])
    }

    @Test func appendAndRemove() {
        var list = MRUList([1])
        list.appendIfMissing(2)
        list.appendIfMissing(1)
        #expect(list.items == [1, 2])
        list.remove(1)
        #expect(list.items == [2])
    }
}
