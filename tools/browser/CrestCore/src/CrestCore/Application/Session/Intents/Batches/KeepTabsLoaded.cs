using CrestCore.Application;

namespace CrestCore.Contracts;

/// Keeps the pages of the tabs a person selected in a window loaded while they
/// are not shown, or lets them unload again when `Keeps` is false. A selected
/// folder's tabs are included. Refused with `WebPagesOnly` for a tab that shows
/// no web page.
public sealed record KeepTabsLoaded(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, bool Keeps)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var batch = workspace.Selecting(turn.Basis, WindowId, SpaceId, Selection);
        batch.Edited.KeepSelectedLoaded(batch.Selected, Keeps);
        return batch.Result(turn.Basis, SyncStaging.Batch);
    }

    #endregion
}
