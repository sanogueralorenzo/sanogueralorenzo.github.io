using CrestCore.Application;

namespace CrestCore.Contracts;

/// Ends a split. Its tabs stay where they are.
public sealed record DissolveSplit(Guid WorkspaceId, Guid SpaceId, Guid GroupId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => {
            edited.DissolveSplit(GroupId, turn.Now);
            edited.PruneSplitMetadata();
        });

    #endregion
}
