using CrestCore.Application;

namespace CrestCore.Contracts;

/// Collapses a folder in the sidebar, or expands it.
public sealed record CollapseFolder(Guid WorkspaceId, Guid SpaceId, Guid FolderId, bool Collapsed) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => edited.CollapseFolder(FolderId, Collapsed, turn.Now));

    #endregion
}
