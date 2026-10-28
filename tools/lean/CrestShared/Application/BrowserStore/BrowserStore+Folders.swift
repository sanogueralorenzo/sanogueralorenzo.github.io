import Foundation

extension BrowserStore {

    @discardableResult
    func createTabFolder(_ tabs: [UUID], in spaceID: UUID, detachesSplitMembers: Bool = false) -> UUID? {
        guard !isDeleting(spaceID),
            let id = createSessionTabFolder(tabs, in: spaceID, detachesSplitMembers: detachesSplitMembers)
        else { return nil }
        return id
    }

    @discardableResult
    func fileTabs(
        _ tabs: [UUID], matching assignment: BrowserSpaceRuntimeAssignment,
        into folderID: UUID?, location: BrowserFolderLocation, before anchor: UUID? = nil,
        beforeFolderID: UUID? = nil, detachesSplitMembers: Bool = false
    ) -> Bool {
        guard spaceModel(matching: assignment) != nil,
            fileSessionTabs(
                tabs, in: assignment.spaceID, into: folderID, location: location, before: anchor,
                beforeFolderID: beforeFolderID, detachesSplitMembers: detachesSplitMembers)
        else { return false }
        return true
    }

    @discardableResult
    func moveFolder(
        _ id: UUID, matching assignment: BrowserSpaceRuntimeAssignment,
        to location: BrowserFolderLocation, into parentID: UUID? = nil,
        before siblingID: UUID? = nil, beforeTabID: UUID? = nil
    ) -> Bool {
        guard spaceModel(matching: assignment) != nil,
            moveSessionFolder(
                id, in: assignment.spaceID, into: parentID, before: siblingID,
                location: location, beforeTabID: beforeTabID)
        else { return false }
        return true
    }
}
