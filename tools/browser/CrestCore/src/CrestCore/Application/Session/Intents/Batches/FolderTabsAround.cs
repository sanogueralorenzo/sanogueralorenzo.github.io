using CrestCore.Application;

namespace CrestCore.Contracts;

/// Puts the tab `TabId` and the tabs a person selected in a window into a new
/// open-tabs folder the core makes in that tab's place, named "New Folder" in
/// the default folder color, holding that tab first. Refused with
/// `InvalidFolderPlacement` when `TabId` is not an open tab at the top level,
/// or is in a split or the selection, or is a Start Page.
public sealed record FolderTabsAround(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, Guid TabId)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var batch = workspace.Selecting(turn.Basis, WindowId, SpaceId, Selection);
        batch.Edited.FolderSelectedAround(batch.Selected, TabId, NativeSessionAuthority.NewFolderTitle, FolderState.DefaultColor, turn.Ids,
            turn.Now);
        return batch.Result(turn.Basis, SyncStaging.Batch);
    }

    #endregion
}
