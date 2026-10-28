using CrestCore.Application;

namespace CrestCore.Contracts;

/// Deletes the tabs a person selected in a window, saved and pinned ones
/// included, into the archive as open tabs. The window then shows the tab it
/// showed before, when the one it showed was deleted, or none. It is saved
/// with the sync journal, as a deletion, before the intent returns.
public sealed record DeleteTabs(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var batch = workspace.Selecting(turn.Basis, WindowId, SpaceId, Selection);
        batch.FollowUp.ShowTab(batch.Space.Id, batch.Edited.DeleteSelected(batch.Selected, batch.Shown, batch.Fallback(), turn.Now));
        return batch.Result(turn.Basis, SyncStaging.BatchDeletion);
    }

    #endregion
}
