using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Drops the lift on another Space of the workspace, to the end of each tab's
/// own section there, and the window follows it when `Follows`. One tab moves
/// as `MoveTabToSpace` moves it; any other lift as `MoveTabsToSpace` moves it.
/// Refused with `PinnedTabsStayPut` for a lift of several pinned tabs.
public sealed record DropOnSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, Guid DestinationSpaceId,
    bool Follows) : SidebarDrop(WorkspaceId, WindowId, SpaceId, Selection) {
    #region Actions - Session

    internal override SessionIntent Committed(NativeSessionAuthority.Lift lift, IIdSource ids) {
        if (lift.Alone is { } tab)
            return new MoveTabToSpace(WorkspaceId, WindowId, SpaceId, tab.Id, DestinationSpaceId, Placement: null, FolderId: null,
                BeforeTabId: null, Follows);
        return lift.PinsOnly
            ? throw new Rejected(new PinnedTabsStayPut())
            : new MoveTabsToSpace(WorkspaceId, WindowId, SpaceId, Selection, DestinationSpaceId, Follows);
    }

    #endregion
}
