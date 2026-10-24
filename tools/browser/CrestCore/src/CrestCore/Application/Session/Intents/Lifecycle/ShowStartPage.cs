using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Shows a Start Page in a Space: the window that asked shows the Space's first
/// open Start Page, or, when `OutsideSplits`, its first one in no split; when
/// the Space has none, a new one, `TabId`, opens after the tab the window
/// shows there. A window returning to a Space asks for one outside splits, so
/// it never lands on half of a split.
public sealed record ShowStartPage(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, bool OutsideSplits)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Shows the Space's first open Start Page, outside splits when asked, or
    /// opens one after the tab the window shows there. Showing the one it has
    /// records its use, as showing a tab does.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        var edited = BrowserTabCollection.Restore(space);
        var draft = space.Tabs.FirstOrDefault(tab => tab.IsStartPage && !tab.Placement.IsDurable
            && (!OutsideSplits || edited.SplitMembers(tab.Id).Count < 2));
        if (draft is null)
            return new OpenTab(WorkspaceId, WindowId, space.Id, TabId,
                new TabContent(Address: null, View: null, Title: null), TabPlacement.Current,
                AfterTabId: followUp.Window?.Tab(space.Id), Shows: true).Edit(workspace, turn);
        followUp.ShowTab(space.Id, draft.Id).ShowSpace(space.Id);
        var used = StoredSessionCodec.Date(StoredSessionCodec.Seconds(turn.Now));
        var tabs = space.Tabs.Select(tab => tab.Id == draft.Id ? tab with { LastActivatedAt = used } : tab);
        return new(NativeSessionAuthority.Replacing(turn.Basis, space with { Tabs = [.. tabs] }),
            SyncStaging.TabUse, followUp);
    }

    #endregion
}
