using CrestCore.Application;

namespace CrestCore.Contracts;

/// Opens `Address` for the window that asked, in a Space it shows: a Start Page
/// the window shows there takes the address, as `NavigateTab` gives one, and
/// otherwise a new tab, `TabId`, opens it after the tab the window shows. The
/// window shows the tab either way. Refused as `NavigateTab` and `OpenTab`
/// refuse.
public sealed record OpenAddress(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, string Address)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Opens an address for the window that asked: a Start Page it shows in
    /// the Space takes the address, and otherwise a new tab opens it after the
    /// tab it shows. The window shows the tab either way.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        var shown = followUp.Window?.Tab(space.Id) is { } shownId ? space.Tabs.FirstOrDefault(tab => tab.Id == shownId) : null;
        if (shown is not { IsStartPage: true })
            return new OpenTab(WorkspaceId, WindowId, space.Id, TabId,
                new TabContent(Address, View: null, Title: null), TabPlacement.Current, AfterTabId: shown?.Id,
                Shows: true).Edit(workspace, turn);
        // Navigating a tab always edits the session.
        var navigated = new NavigateTab(WorkspaceId, space.Id, shown.Id, Address).Edit(workspace, turn)!;
        followUp.ShowTab(space.Id, shown.Id).ShowSpace(space.Id);
        return navigated with { FollowUp = followUp };
    }

    #endregion
}
