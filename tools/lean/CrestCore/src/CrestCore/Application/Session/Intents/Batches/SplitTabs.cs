using CrestCore.Application;

namespace CrestCore.Contracts;

/// Combines the tabs a person selected in a window in one split: each joins
/// the split of `TargetTabId`, or of the first selected tab, at member `Index`
/// and on, or after the others. A saved or pinned tab stays where it is and an
/// open copy joins in its place, starting from where its source's page is now,
/// published as `TabCopied`. The window shows the last tab that joined.
/// Refused with `SplitNeedsTwoTabs` or `SplitLimitReached` when the split would
/// hold fewer than two tabs or more than it can.
public sealed record SplitTabs(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, Guid? TargetTabId, int? Index)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var batch = workspace.Selecting(turn.Basis, WindowId, SpaceId, Selection);
        var (shown, copies) = batch.Edited.SplitSelected(batch.Selected, TargetTabId, Index, batch.Shown, turn.Ids, turn.Now);
        batch.FollowUp.ShowTab(batch.Space.Id, shown);
        return batch.Result(turn.Basis, SyncStaging.Batch, workspace.StartingCopies(batch, copies, WindowId, turn.Pages));
    }

    #endregion
}
