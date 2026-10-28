using CrestCore.Application;

namespace CrestCore.Contracts;

/// Puts the tabs and folders a person selected in a window into a new folder
/// the core makes at the top level of `Placement`'s section, named `Title`,
/// which the app sends in its own language, in the default folder color. A selected folder moves in whole, as a
/// folder of the new one. Refused with `InvalidFolderPlacement` for a section
/// that holds no folders.
public sealed record FolderTabs(
    Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, TabPlacement Placement, string? Title = null)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var batch = workspace.Selecting(turn.Basis, WindowId, SpaceId, Selection);
        batch.Edited.FolderSelected(batch.Selected, Placement, NativeSessionAuthority.FolderTitle(Title), FolderState.DefaultColor, turn.Ids,
            turn.Now);
        return batch.Result(turn.Basis, SyncStaging.Batch);
    }

    #endregion
}
