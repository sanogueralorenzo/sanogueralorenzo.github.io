using CrestCore.Application;

namespace CrestCore.Contracts;

/// Moves a tab to member `Index` of its split, clamped to the split's members.
public sealed record MoveSplitMember(Guid WorkspaceId, Guid SpaceId, Guid TabId, int Index) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => edited.MoveSplitMember(TabId, Index, turn.Now));

    #endregion
}
