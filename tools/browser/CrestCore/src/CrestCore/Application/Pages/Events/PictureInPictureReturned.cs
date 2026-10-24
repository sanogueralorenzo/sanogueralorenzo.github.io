using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person pressed the control of a page's Picture in Picture window that
/// returns its video to the page. The engine ends the Picture in Picture and
/// puts the video back in the page itself; the core shows the person the page.
public sealed record PictureInPictureReturned(Guid PageId) : PageEvent(PageId) {
    #region Actions - Pages

    /// The page's tab shows in the window that hosts the page, which switches
    /// to the tab's Space if it must, and that window comes to the front. When
    /// the page's window has closed, another window over its workspace shows
    /// the tab, preferring one that shows the tab's Space; with none open,
    /// nothing does, since returning never opens a window. A page without a
    /// tab, one whose tab is gone, and one whose Space is locked or being
    /// deleted show nothing.
    internal override void Apply(Pages pages, Page page, PageTurn turn) {
        if (page.TabId is not { } tabId || pages.Tab(page) is null || pages.Shown(page) is null
            || pages.Device.ReturnWindow(page.WorkspaceId, page.SpaceId, page.WindowId) is not { } windowId)
            return;
        new ShowTab(windowId, page.SpaceId, tabId).Apply(pages.Device, new DeviceTurn(turn.Changes, pages.Clock.Now, pages.Ids, pages));
        // The engine returned the video itself, so the page coming back on
        // screen asks it for nothing more.
        page.Seen(isShown: true, pages.Clock.Now);
        pages.RecoverShown(turn.Changes, turn.Issue);
        turn.Changes.Publish(new WindowBroughtForward(windowId));
    }

    #endregion
}
