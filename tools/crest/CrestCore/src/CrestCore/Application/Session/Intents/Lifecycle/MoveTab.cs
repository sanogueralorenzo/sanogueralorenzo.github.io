using CrestCore.Application;

namespace CrestCore.Contracts;

/// Moves a tab into `FolderId`, or to the top level of `Placement`'s section,
/// before the tab `BeforeTabId` names or after the section's last tab. A split
/// member moving to a section that holds no splits leaves its split; elsewhere
/// it keeps it unless `LeavesSplit` takes it out. Refused with
/// `PinnedTabsFull` for a full section, and `UnknownFolder` or
/// `InvalidFolderPlacement` for a folder that is not there or not in the
/// section.
public sealed record MoveTab(Guid WorkspaceId, Guid SpaceId, Guid TabId, TabPlacement Placement, Guid? FolderId, Guid? BeforeTabId,
    bool LeavesSplit) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Moves the tab, which leaves its split for a section that holds none.
    /// One that leaves its split takes the split's metadata with it when no
    /// other tab keeps it.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => {
            bool leaves = LeavesSplit || !Placement.HoldsSplits;
            edited.MoveTab(TabId, Placement, FolderId, BeforeTabId, leaves, turn.Now);
            if (leaves) edited.PruneSplitMetadata();
        });

    #endregion
}
