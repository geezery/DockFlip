import Foundation

/// Which Clean Up rows are ticked when the list is read again (after Close Selected,
/// Keep, or opening the window once more). Apart from AppKit so it can be tested.
enum CleanupSelection {
    /// A row the user unticked stays unticked for as long as it is listed: re-ticking it
    /// would let the next Close Selected close what the user chose to keep. Only rows
    /// that were not listed before come in ticked, as every row does on the first look.
    ///
    /// `comeBackUnticked` are rows that are new only because the user just removed their
    /// app from "Kept Apps": that says "suggest it again", not "close it", so they come in
    /// unticked. Rows of it that were already listed keep their tick state like any other.
    static func afterReload<Target: Hashable>(
        listed: [Target],
        previouslyListed: Set<Target>,
        selected: Set<Target>,
        comeBackUnticked: Set<Target> = []
    ) -> Set<Target> {
        Set(listed.filter {
            selected.contains($0) || (!previouslyListed.contains($0) && !comeBackUnticked.contains($0))
        })
    }
}
