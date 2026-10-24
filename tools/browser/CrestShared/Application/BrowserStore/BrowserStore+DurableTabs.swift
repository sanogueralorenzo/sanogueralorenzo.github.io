import Foundation

extension BrowserStore {
    /// Records an explicit close without removing the durable tab or archiving
    /// it: the core puts its page away, back at its saved address when the
    /// app's preferences say so. The page owner retires its runtime before
    /// publishing this session change.
    @discardableResult
    func closeDurableTab(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        let spaceAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: assignment.spaceID, profileID: assignment.profileID
        )
        guard let space = spaceModel(matching: spaceAssignment),
            let tab = space.tabs.model(assignment.tabID),
            tab.placement.isDurable
        else { return false }
        // The core returns the window to the tab it showed before, skipping the
        // closed tab's split, whose other members would present it again.
        return closeSessionTab(tab.id, in: space.id)
    }
}
