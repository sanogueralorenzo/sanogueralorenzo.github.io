using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Drops the lift into one list of the Space's sidebar: the inside of
/// `FolderId`, or the top level of `Section`, before the tab `BeforeTabId` or
/// the folder `BeforeFolderId`, or at its end. Onto a collapsed folder's row is
/// at the end of its inside. One tab moves as `FileTabs` moves it, or among the
/// pinned tabs as `MoveTab` does; any other lift is filed as `FileTabs` files
/// it. Refused with `PinsOneTabAtATime` for a lift that is not only pinned tabs
/// dropped among the pinned tabs.
public sealed record DropIntoList(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, TabPlacement Section,
    Guid? FolderId, Guid? BeforeTabId, Guid? BeforeFolderId) : SidebarDrop(WorkspaceId, WindowId, SpaceId, Selection) {
    #region Actions - Session

    internal override SessionIntent Committed(NativeSessionAuthority.Lift lift, IIdSource ids) {
        if (lift.Alone is { } tab)
            return Section.HoldsFolders
                ? new FileTabs(WorkspaceId, WindowId, SpaceId, Selection, Section, FolderId, BeforeTabId, BeforeFolderId,
                    LeavesSplits: true)
                : new MoveTab(WorkspaceId, SpaceId, tab.Id, Section, FolderId, BeforeTabId, LeavesSplit: true);
        return Section.HoldsFolders || lift.PinsOnly
            ? new FileTabs(WorkspaceId, WindowId, SpaceId, Selection, Section, FolderId, BeforeTabId, BeforeFolderId, LeavesSplits: false)
            : throw new Rejected(new PinsOneTabAtATime());
    }

    #endregion
}
