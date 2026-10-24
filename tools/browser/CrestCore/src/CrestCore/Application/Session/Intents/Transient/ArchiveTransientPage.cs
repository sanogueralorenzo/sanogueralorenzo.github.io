using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Keeps a Quick Window's page, `PageId`, in its Space's archive as a closed
/// open tab at the address and title it shows, so it can be found again. The
/// page may already be gone, as one memory pressure took back is; the core
/// keeps what it showed last. A page still open must live in `SpaceId`.
/// Refused when the page was already kept or archived, when it lives in
/// another Space, when the core no longer knows it, and when the Space is
/// locked or being deleted.
public sealed record ArchiveTransientPage(Guid WorkspaceId, Guid PageId, Guid SpaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Archives the page as a closed open tab of its Space, at the address and
    /// title it shows, or showed last when it is already gone.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequirePendingTransient(PageId);
        var space = workspace.Editable(turn.Basis, SpaceId);
        var page = workspace.Known(PageId, turn.Pages);
        if (page.SpaceId != space.Id || page.ProfileId != space.ProfileId) throw new Rejected(new PageProfileMismatch(page.Id, space.Id));
        var edited = BrowserTabCollection.Restore(space);
        edited.ArchiveTransient(workspace.NewTab(turn.Ids.Next(), new TabContent(page.Address, View: null, page.Title),
            TabPlacement.Current, turn.Now), turn.Now);
        return new(NativeSessionAuthority.Replacing(turn.Basis, edited.Capture(space)), SyncStaging.Edit, Completes: PageId);
    }

    #endregion

    #region Actions - Routing

    /// An archived page is no longer remembered as one its owner unloaded.
    internal override void Commit(CrestApp app, ChangeFeed changes) {
        base.Commit(app, changes);
        app.Pages.ForgetUnloaded(PageId);
    }

    #endregion
}
