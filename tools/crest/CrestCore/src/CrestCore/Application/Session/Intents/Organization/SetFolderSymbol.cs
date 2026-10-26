using CrestCore.Application;

namespace CrestCore.Contracts;

/// Gives a folder its icon: an SF Symbol name or an emoji.
public sealed record SetFolderSymbol(Guid WorkspaceId, Guid SpaceId, Guid FolderId, string Symbol) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => edited.SetFolderSymbol(FolderId, Symbol));

    #endregion
}
