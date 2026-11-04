import CoreGraphics

/// Whether a window's kept picture still shows it, so a window is captured only
/// when it may look different. Pure, unit-tested.
///
/// A window that sat in the background since its picture was taken looks the
/// same, as far as anyone choosing it from ⌘Tab or the Dock can tell. So a
/// window is pictured again only when:
/// - it has no picture yet,
/// - it was the active window at some point after its picture was taken, or is
///   the active one now (someone worked in it),
/// - its title or size changed since (a browser on another tab, another workbook).
/// Moving a window changes nothing in its picture. A window that changes on its
/// own in the background (a video, a chat) keeps the look it had when it was left.
struct PreviewFreshness<ID: Hashable> {
    /// What a picture is compared against: the window's title and size.
    struct Signature: Equatable {
        let title: String
        let width: Int
        let height: Int

        init(title: String, size: CGSize) {
            self.title = title
            width = Int(size.width.rounded())
            height = Int(size.height.rounded())
        }
    }

    /// How many times each window became or stopped being the active window.
    private var uses: [ID: Int] = [:]
    /// Each pictured window's signature, and its use count when its capture started.
    private var pictures: [ID: (signature: Signature, uses: Int)] = [:]

    /// The window became the active one, or stopped being it.
    mutating func used(_ id: ID) {
        uses[id, default: 0] += 1
    }

    /// The use count to hand to `pictured(_:as:usesAtStart:)`, read as a capture starts:
    /// work in the window while it is being captured leaves the picture out of date.
    func usesNow(_ id: ID) -> Int {
        uses[id, default: 0]
    }

    /// A picture of the window was kept.
    mutating func pictured(_ id: ID, as signature: Signature, usesAtStart: Int) {
        pictures[id] = (signature, usesAtStart)
    }

    /// True when the window should be captured (again).
    func needsPicture(_ id: ID, now signature: Signature, isActive: Bool) -> Bool {
        guard let picture = pictures[id] else { return true }
        return isActive || picture.uses != uses[id, default: 0] || picture.signature != signature
    }

    /// The window closed, or its picture was dropped.
    mutating func forget(_ id: ID) {
        pictures[id] = nil
        uses[id] = nil
    }

    /// Keeps only the windows in `ids`.
    mutating func keepOnly(_ ids: Set<ID>) {
        pictures = pictures.filter { ids.contains($0.key) }
        uses = uses.filter { ids.contains($0.key) }
    }

    mutating func forgetAll() {
        pictures = [:]
        uses = [:]
    }
}
