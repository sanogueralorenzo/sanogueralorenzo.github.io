using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Keeps a Quick Window's or Peek's page, `PageId`, as a new tab of a Space
/// in `Placement`'s section, after the tab the window that asked shows there.
/// The core gives the tab its identity and the address the page shows, and
/// that window shows it and its Space. The tab takes the page itself when the
/// page's engine can move it between windows and the page already lives in
/// that Space; the core says which in `TransientPagePromoted`. Refused when
/// the page was already kept or archived, when its own Space no longer keeps
/// its profile, and when either Space is locked or being deleted.
public sealed record PromoteTransientPage(Guid WorkspaceId, Guid WindowId, Guid PageId, Guid SpaceId, TabPlacement Placement)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Keeps the page as a new tab at the address it shows, after the one the
    /// issuing window shows in the Space, which that window then shows. The
    /// tab takes the live page when the page lives in that Space and its
    /// engine can move it between windows.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequirePendingTransient(PageId);
        var page = workspace.Known(PageId, turn.Pages);
        var source = workspace.Editable(turn.Basis, page.SpaceId);
        if (source.ProfileId != page.ProfileId) throw new Rejected(new PageProfileMismatch(page.Id, source.Id));
        var destination = workspace.Editable(turn.Basis, SpaceId);
        var edited = BrowserTabCollection.Restore(destination);
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        var tab = BrowserTab.Restore(workspace.NewTab(turn.Ids.Next(), new TabContent(page.Address, View: null, page.Title),
            Placement, turn.Now));
        edited.InsertTab(tab, followUp.Window?.Tab(destination.Id) is { } shown ? edited.InsertionIndexAfter(shown) : null);
        followUp.ShowTab(destination.Id, tab.Id).ShowSpace(destination.Id);
        var adopts = page.MovesBetweenWindows && page.SpaceId == destination.Id && page.ProfileId == destination.ProfileId;
        return new(NativeSessionAuthority.Replacing(turn.Basis, edited.Capture(destination)), SyncStaging.Creation, followUp,
            new([], null, new SessionTransientPromotion(page.Id, tab.Id, adopts)), Completes: page.Id);
    }

    #endregion

    #region Actions - Routing

    /// A kept page is no longer remembered as one its owner unloaded.
    internal override void Commit(CrestApp app, ChangeFeed changes) {
        base.Commit(app, changes);
        app.Pages.ForgetUnloaded(PageId);
    }

    #endregion
}
