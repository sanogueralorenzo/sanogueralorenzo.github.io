using CrestCore.Application;

namespace CrestCore.Contracts;

/// A page's navigation finished at `Url`, titled `Title`, which is empty for a
/// page that has no title of its own yet. The core records the first finish
/// of each document: the tab that owns the page shows the address and title,
/// and the Space's history holds a visit. A move within the document finishes
/// once its title settles. A title the page gives the document later reaches
/// the record through `PageStateChanged`.
public sealed record NavigationFinished(Guid PageId, string Url, string Title) : PageEvent(PageId) {
    #region Actions - Pages

    /// The record waits while a transaction holds the workspace's session.
    internal override void Apply(Pages pages, Page page, PageTurn turn) {
        var now = pages.Clock.Now;
        if (page.Finish(Url, Title, now))
            pages.Edit(page, new NavigationRecord(page.Id, page.SpaceId, now, page.TabId, Url, Title, page.Icon, pages.Ids.Next()),
                turn.Changes);
    }

    #endregion
}
