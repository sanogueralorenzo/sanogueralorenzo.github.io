using CrestCore.Application;

namespace CrestCore.Contracts;

/// Archives the open tabs a person selected in a window. The window then shows
/// the tab it showed before, when the one it showed was archived, or none.
/// Refused with `CurrentTabsOnly` for a saved or pinned tab, which closes only
/// on its own, and by the rules every selection answers to: see
/// `SelectionChanged`, `IncompleteSplit` and `SelectionHoldsFolders`.
public sealed record CloseTabs(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var batch = workspace.Selecting(turn.Basis, WindowId, SpaceId, Selection);
        batch.FollowUp.ShowTab(batch.Space.Id, batch.Edited.CloseSelected(batch.Selected, batch.Shown, batch.Fallback(), turn.Now));
        return batch.Result(turn.Basis, SyncStaging.Batch);
    }

    #endregion
}
