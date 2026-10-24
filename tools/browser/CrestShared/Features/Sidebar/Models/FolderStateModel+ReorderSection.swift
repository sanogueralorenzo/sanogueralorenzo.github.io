extension FolderStateModel {
    /// The run of rows the folder's own row reorders within: the tabs of its
    /// section, inside its parent or at the section's top level.
    var reorderSection: BrowserSidebarReorderSection {
        .tabs(placement: location, folderID: parentID)
    }
}
