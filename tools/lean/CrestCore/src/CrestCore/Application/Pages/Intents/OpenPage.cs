using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record OpenPage(Guid PageId, Guid WorkspaceId, Guid SpaceId, Guid? TabId, Guid WindowId,
    TransientPresentation? Transient = null, Guid? OpenerPageId = null) : PageIntent {
    #region Actions - Pages

    /// Reopen a tab on WebKit, taking its retained browser history and native
    /// state when the tab still shows the same address.
    internal override void Apply(Pages pages, PageTurn turn) {
        if (pages.IsOpen(PageId)) throw new Rejected(new DuplicatePage(PageId));
        var workspace = pages.Device.Workspace(WorkspaceId);
        pages.Device.Opened(WindowId);
        var space = pages.Hosting(workspace, SpaceId);
        pages.RequireUnowned(WorkspaceId, WindowId, TabId, moving: null);
        var opener = pages.Opener(OpenerPageId, WorkspaceId, space);
        var history = TabId is { } kept && opener is null ? pages.KeptHistory(WorkspaceId, space, kept) : null;
        var engine = pages.Opening(opener)
            ?? throw new Rejected(new EngineNotRegistered());
        var page = new Page(PageId, engine, space.ProfileId, WorkspaceId, space.Id, TabId, WindowId, Transient,
            openedByPage: opener is not null);
        pages.Add(page);
        var restore = TabId is { } tabId ? pages.Restorable(WorkspaceId, space, tabId) : null;
        if (restore is not null) page.Restoring(restore.Url);
        if (history is { } resumed) page.Resume(resumed.History, restores: restore is not null || resumed.Archived);
        turn.Changes.Publish(new PageOpened(page.State));
        turn.Issue(engine, new CreatePage(page.Id, page.ProfileId, workspace.IsPrivateBrowsing, page.WindowId, restore));
    }

    #endregion
}
