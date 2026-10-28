using CrestCore.Contracts;

namespace CrestCore.Application;

/// Shows what an engine's tab group became as the folder of the same identity
/// in a Space, in one edit: makes the folder in the open tabs when the Space
/// has none, takes the group's title, color or collapsed state where it gave
/// one, moves the tabs `LeavingTabIds` names out to the folder's own level,
/// just after it, and files the tabs `JoiningTabIds` names into it, each taken
/// out of its split as Chrome takes a grouped tab out of one. The core sends
/// it for a change an extension made; no platform does.
internal sealed record ShowTabGroup(Guid WorkspaceId, Guid SpaceId, Guid FolderId, string? Title, BrandColor? Color,
    bool? IsCollapsed, IReadOnlyList<Guid> JoiningTabIds, IReadOnlyList<Guid> LeavingTabIds) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// A group the Space has no folder for is shown only once a tab joins it.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var existing = workspace.Editable(turn.Basis, SpaceId).Folders.FirstOrDefault(folder => folder.Id == FolderId);
        if (existing is null && JoiningTabIds.Count == 0) return null;
        return workspace.Organizing(turn.Basis, SpaceId, existing is null ? SyncStaging.Creation : SyncStaging.Edit, edited => {
            if (existing is null) edited.AddFolder(FolderId, Title ?? string.Empty, TabPlacement.Current);
            else if (Title is { } title) edited.RenameFolder(FolderId, title);
            if (Color is { } color) edited.SetFolderColor(FolderId, color);
            if (IsCollapsed is { } collapsed) edited.CollapseFolder(FolderId, collapsed, turn.Now);
            var folder = edited.Folders.First(candidate => candidate.Id == FolderId);
            if (LeavingTabIds.Count > 0) {
                var leaving = LeavingTabIds.ToHashSet();
                var tabs = edited.Tabs;
                int last = tabs.ToList().FindLastIndex(tab => tab.FolderId == FolderId);
                var after = tabs.Skip(last + 1).FirstOrDefault(tab => !leaving.Contains(tab.Id) && tab.Placement == folder.Location);
                edited.FileTabs(LeavingTabIds, folder.Location, folder.ParentId, turn.Now,
                    before: after is { } next && next.FolderId == folder.ParentId ? next.Id : null);
            }
            if (JoiningTabIds.Count > 0) edited.FileTabs(JoiningTabIds, folder.Location, FolderId, turn.Now, detachSplitMembers: true);
        });
    }

    #endregion
}
