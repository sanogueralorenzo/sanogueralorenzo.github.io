using CrestCore.Application;

namespace CrestCore.Contracts;

/// Takes a tab out of its split, after the split's last member. A split left
/// with one member ends.
public sealed record LeaveSplit(Guid WorkspaceId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => {
            edited.LeaveSplit(TabId, turn.Now);
            edited.PruneSplitMetadata();
        });

    #endregion
}
