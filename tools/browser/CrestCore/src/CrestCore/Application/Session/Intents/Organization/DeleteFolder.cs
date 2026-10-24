using CrestCore.Application;

namespace CrestCore.Contracts;

/// Deletes a folder. Its tabs and folders move up into its parent, or to the
/// top level of its section.
public sealed record DeleteFolder(Guid WorkspaceId, Guid SpaceId, Guid FolderId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Deletion, edited => edited.DeleteFolder(FolderId, turn.Now));

    #endregion
}
