using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Drops the lift on the open tab `TabId`, putting that tab and then the lift
/// into a new open-tabs folder in its place, named "New Folder" in the default
/// folder color. One tab goes in as `CreateFolder` puts it, leaving its split;
/// any other lift as `FolderTabsAround` does. Refused with
/// `InvalidFolderPlacement` when `TabId` is not an open tab at the top level,
/// or is in a split or the lift, or is a Start Page.
public sealed record DropAroundTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, Guid TabId)
    : SidebarDrop(WorkspaceId, WindowId, SpaceId, Selection) {
    #region Actions - Session

    internal override SessionIntent Committed(NativeSessionAuthority.Lift lift, IIdSource ids) {
        if (lift.Alone is not { } tab) return new FolderTabsAround(WorkspaceId, WindowId, SpaceId, Selection, TabId);
        return FoldsAround(lift.Work.Edited, tab.Id)
            ? new CreateFolder(WorkspaceId, SpaceId, ids.Next(), TabPlacement.Current, ParentId: null, Title: null,
                FolderState.DefaultColor, FolderState.DefaultSymbol, [TabId, tab.Id], LeavesSplits: true)
            : throw new Rejected(new InvalidFolderPlacement());
    }

    /// Whether a new folder may be made around the open tab `TabId` for
    /// `tabId`: it is an open tab at the top level, in no split, not a Start
    /// Page, and not the tab itself.
    private bool FoldsAround(BrowserTabCollection organization, Guid tabId) {
        var target = organization.Tab(TabId);
        return TabId != tabId && !target.Placement.IsDurable && target.FolderId is null && target.SplitGroupId is null
            && !target.Content.IsStartPage;
    }

    #endregion
}
