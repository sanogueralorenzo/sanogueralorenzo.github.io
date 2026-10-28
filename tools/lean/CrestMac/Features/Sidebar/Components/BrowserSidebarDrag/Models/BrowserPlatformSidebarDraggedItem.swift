import Foundation

/// What a lifted sidebar row does on macOS beyond what every shell shares: it
/// resolves the art its floating lift shows, out of the Space it was lifted in.
protocol BrowserPlatformSidebarDraggedItem {
    /// What the floating lift of this row alone shows, resolved in `space`,
    /// or nil once the Space no longer holds it. `previewRows` are the rows
    /// measured inside a lifted folder.
    @MainActor
    func liftPreviewSubject(
        in space: SpaceModel, previewRows: [BrowserSidebarReorderRow]
    ) -> BrowserSidebarLiftPreviewSubject?
}

extension BrowserTabDragItem {
    // MARK: - Actions - Lift Preview

    /// The tab itself.
    @MainActor
    func liftPreviewSubject(
        in space: SpaceModel, previewRows: [BrowserSidebarReorderRow]
    ) -> BrowserSidebarLiftPreviewSubject? {
        space.tabs.model(tabID).map(BrowserSidebarLiftPreviewSubject.tab)
    }
}

extension BrowserFolderDragItem {
    // MARK: - Actions - Lift Preview

    /// The folder with the rows measured inside it.
    @MainActor
    func liftPreviewSubject(
        in space: SpaceModel, previewRows: [BrowserSidebarReorderRow]
    ) -> BrowserSidebarLiftPreviewSubject? {
        let rows = BrowserFolderDragPreviewRow.resolve(previewRows, in: space, rootFolderID: folderID)
        return space.folders.model(folderID).map { .folder($0, rows: rows) }
    }
}

extension BrowserSplitGroupDragItem {
    // MARK: - Actions - Lift Preview

    /// The split's members. A run that has already lost its members has
    /// nothing to draw; the drag itself is ended by the same change.
    @MainActor
    func liftPreviewSubject(
        in space: SpaceModel, previewRows: [BrowserSidebarReorderRow]
    ) -> BrowserSidebarLiftPreviewSubject? {
        let members = space.splitMembers(of: groupID)
        return members.isEmpty ? nil : .splitGroup(members)
    }
}
