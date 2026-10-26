using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Drops the lift on the cards a window shows, joining the split of
/// `TargetTabId`, the tab it shows, as the card at `Index` or after the others.
/// One tab joins as `JoinSplit` joins it; any other lift as `SplitTabs` joins
/// it. Refused with `PinnedTabsStayPut` for a lift of several pinned tabs.
public sealed record DropIntoSplit(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, Guid TargetTabId, int? Index)
    : SidebarDrop(WorkspaceId, WindowId, SpaceId, Selection) {
    #region Actions - Session

    internal override SessionIntent Committed(NativeSessionAuthority.Lift lift, IIdSource ids) {
        if (lift.Alone is { } tab) return new JoinSplit(WorkspaceId, WindowId, SpaceId, tab.Id, TargetTabId, Index);
        return lift.PinsOnly
            ? throw new Rejected(new PinnedTabsStayPut())
            : new SplitTabs(WorkspaceId, WindowId, SpaceId, Selection, TargetTabId, Index);
    }

    #endregion
}
