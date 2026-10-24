using CrestCore.Application;

namespace CrestCore.Contracts;

/// Moves a split's tabs, in order, into `FolderId` or to the top level of
/// `Placement`'s section, before the tab `BeforeTabId` names.
public sealed record MoveSplit(Guid WorkspaceId, Guid SpaceId, Guid GroupId, TabPlacement Placement, Guid? FolderId, Guid? BeforeTabId)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited =>
            edited.MoveSplitGroup(GroupId, Placement, FolderId, BeforeTabId, turn.Now));

    #endregion
}
