using CrestCore.Application;

namespace CrestCore.Contracts;

/// Pins a tab at the end of the pinned tabs, out of its split, or returns a
/// pinned tab to the end of the open tabs. Refused as `MoveTab` refuses,
/// with `PinnedTabsFull` when no tab more fits among the pinned.
public sealed record TogglePin(Guid WorkspaceId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Moves a pinned tab to the open tabs and any other tab to the pinned
    /// tabs, each at the end of its section.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var pinned = workspace.Editable(turn.Basis, SpaceId).Tabs.FirstOrDefault(tab => tab.Id == TabId)?.Placement == TabPlacement.Pinned;
        return new MoveTab(WorkspaceId, SpaceId, TabId,
            pinned ? TabPlacement.Current : TabPlacement.Pinned, FolderId: null, BeforeTabId: null, LeavesSplit: false)
            .Edit(workspace, turn);
    }

    #endregion
}
