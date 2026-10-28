using CrestCore.Application;

namespace CrestCore.Contracts;

/// Dissolves every split the tabs a person selected in a window belong to.
public sealed record SeparateSplits(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var batch = workspace.Selecting(turn.Basis, WindowId, SpaceId, Selection);
        batch.Edited.SeparateSelected(batch.Selected, turn.Now);
        return batch.Result(turn.Basis, SyncStaging.Batch);
    }

    #endregion
}
