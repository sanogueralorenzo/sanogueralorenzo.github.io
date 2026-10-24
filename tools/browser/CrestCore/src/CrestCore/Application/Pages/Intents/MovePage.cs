using CrestCore.Application;

namespace CrestCore.Contracts;

/// Gives a page a new owner without recreating it: a tab in another
/// workspace or window, or a tab that adopts a transient request's page. The
/// engine page stays in its profile, so the destination Space must keep the
/// same one. Refused like `OpenPage`, and when the destination keeps another
/// profile.
public sealed record MovePage(Guid PageId, Guid WorkspaceId, Guid SpaceId, Guid? TabId, Guid WindowId) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        var page = pages.Known(PageId);
        var workspace = pages.Device.Workspace(WorkspaceId);
        pages.Device.Opened(WindowId);
        var space = pages.Hosting(workspace, SpaceId);
        if (space.ProfileId != page.ProfileId) throw new Rejected(new PageProfileMismatch(page.Id, space.Id));
        pages.RequireUnowned(WorkspaceId, WindowId, TabId, moving: page);
        var before = page.State;
        page.Move(WorkspaceId, space.Id, TabId, WindowId);
        if (page.State != before) turn.Changes.Publish(new PageChanged(page.State));
    }

    #endregion
}
