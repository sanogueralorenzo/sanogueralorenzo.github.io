using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record OpenPage(Guid PageId, Guid WorkspaceId, Guid SpaceId, Guid? TabId, Guid WindowId,
    TransientPresentation? Transient = null, Guid? OpenerPageId = null) : PageIntent {
    #region Actions - Pages

    /// A tab's page restores what the tab's last page kept, when it closed
    /// keeping its state on the same engine at the address the tab shows. It
    /// takes on that page's history too, and opens on the engine of the entry
    /// that history shows, so going back and forward reach every engine the
    /// tab went through. A history the tab's archive brought back across a
    /// relaunch expects the platform to restore that engine's history.
    internal override void Apply(Pages pages, PageTurn turn) {
        if (pages.IsOpen(PageId)) throw new Rejected(new DuplicatePage(PageId));
        var workspace = pages.Device.Workspace(WorkspaceId);
        pages.Device.Opened(WindowId);
        var space = pages.Hosting(workspace, SpaceId);
        pages.RequireUnowned(WorkspaceId, WindowId, TabId, moving: null);
        var opener = pages.Opener(OpenerPageId, WorkspaceId, space);
        var history = TabId is { } kept && opener is null ? pages.KeptHistory(WorkspaceId, space, kept) : null;
        var engine = (history?.History.Engine is { } shown ? pages.Engines.Registered(shown) : null) ?? pages.Opening(opener)
            ?? throw new Rejected(new EngineNotRegistered());
        var page = new Page(PageId, engine, space.ProfileId, WorkspaceId, space.Id, TabId, WindowId, Transient,
            openedByPage: opener is not null);
        pages.Add(page);
        var restore = TabId is { } tabId ? pages.Restorable(WorkspaceId, space, tabId, engine.Kind) : null;
        if (restore is not null) page.Restoring(restore.Url);
        if (history is { } resumed) page.Resume(resumed.History, restores: restore is not null || resumed.Archived);
        turn.Changes.Publish(new PageOpened(page.State));
        turn.Issue(engine, new CreatePage(page.Id, page.ProfileId, workspace.IsPrivateBrowsing, page.WindowId, restore));
    }

    #endregion
}
