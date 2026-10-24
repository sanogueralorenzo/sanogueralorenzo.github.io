using CrestCore.Application;

namespace CrestCore.Contracts;

/// The engine found an icon for the document a page shows at `Url`, or the
/// color the page's theme puts behind it changed. The binding keeps the
/// image; once the document is recorded, the core has the page's tab wear it
/// when the tab's icon follows its page.
public sealed record PageIconChanged(Guid PageId, string Url, TabIconAccent? Accent) : PageEvent(PageId) {
    #region Actions - Pages

    /// An icon for a recorded document goes to the page's tab, which waits
    /// while a transaction holds the workspace's session.
    internal override void Apply(Pages pages, Page page, PageTurn turn) {
        if (page.ShowIcon(new(Url, Accent)) && page.TabId is { } tabId)
            pages.Edit(page, new IconAdoption(page.Id, page.SpaceId, pages.Clock.Now, tabId, page.Icon!), turn.Changes);
    }

    #endregion
}
