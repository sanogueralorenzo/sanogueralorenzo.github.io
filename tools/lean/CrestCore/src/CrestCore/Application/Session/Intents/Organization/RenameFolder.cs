using CrestCore.Application;

namespace CrestCore.Contracts;

/// Renames a folder. A blank title names it "Untitled Folder".
public sealed record RenameFolder(Guid WorkspaceId, Guid SpaceId, Guid FolderId, string Title) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => edited.RenameFolder(FolderId, Title));

    #endregion
}
