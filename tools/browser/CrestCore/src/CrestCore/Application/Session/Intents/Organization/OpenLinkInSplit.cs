using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Opens `Address` as a new open tab, `TabId`, titled `Title`, and joins it to
/// the split of `TargetTabId` as `JoinSplit` does, copies included. The window
/// that asked shows the new tab.
public sealed record OpenLinkInSplit(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, Guid TargetTabId,
    string Address, string Title) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Opens the link as a new open tab and joins it to the target's split.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (turn.Basis.Spaces.Any(candidate => candidate.Tabs.Any(tab => tab.Id == TabId)))
            throw new Rejected(new TabAlreadyExists(TabId));
        var edited = BrowserTabCollection.Restore(space);
        edited.InsertTab(BrowserTab.Restore(new TabState(TabId, Title, Address, NativeContent: null,
            SavedUrl: null, TabIconMode.WebSymbol, FaviconUrl: null, IconAccent: null, StoredIconMode: null, TabPlacement.Current,
            FolderId: null, SplitGroupId: null, turn.Now, PositionModifiedAt: null, CustomTitle: null, TitleModifiedAt: null,
            KeepsPageLoaded: false)), null);
        return workspace.Joining(turn.Basis, space, edited, WindowId, TabId, TargetTabId, null, turn.Pages, turn.Now, turn.Ids);
    }

    #endregion
}
