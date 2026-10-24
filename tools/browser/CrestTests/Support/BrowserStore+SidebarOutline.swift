import Foundation

@testable import Crest

extension SessionState.Seed {
    /// The identities of the rows the core's sidebar lists for this seed's
    /// Space `spaceID`: the session opens in a window of its own, as a
    /// relaunch opens it.
    @MainActor
    func sidebarRowIDs(
        in spaceID: UUID, location: BrowserFolderLocation, parentID: UUID? = nil
    ) -> [BrowserSidebarReorderItemID] {
        BrowserStore(seed: self).sidebarRowIDs(in: spaceID, location: location, parentID: parentID)
    }
}

extension BrowserStore {
    /// The identities of the rows this window's core lists for the Space
    /// `spaceID`: the top level of `location`'s section, or the inside of
    /// `parentID`.
    func sidebarRowIDs(
        in spaceID: UUID, location: BrowserFolderLocation, parentID: UUID? = nil
    ) -> [BrowserSidebarReorderItemID] {
        guard let space = spaceModel(spaceID) else { return [] }
        let list = parentID.map { space.sidebar.inside($0) } ?? space.sidebar.section(location.tabPlacement)
        return list.rows.map(BrowserSidebarReorderItemID.init)
    }
}
