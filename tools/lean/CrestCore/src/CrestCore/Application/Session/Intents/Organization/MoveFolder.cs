using CrestCore.Application;

namespace CrestCore.Contracts;

/// Moves a folder, with everything inside it, into `ParentId` or to the top
/// level of `Placement`'s section, before `BeforeFolderId` among its new
/// siblings or before the tab `BeforeTabId` names. Without a section or a
/// parent it stays in its own section. A folder never moves into itself.
public sealed record MoveFolder(Guid WorkspaceId, Guid SpaceId, Guid FolderId, TabPlacement? Placement, Guid? ParentId,
    Guid? BeforeFolderId, Guid? BeforeTabId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited =>
            edited.MoveFolder(FolderId, Placement, ParentId, turn.Now, BeforeFolderId, BeforeTabId));

    #endregion
}
