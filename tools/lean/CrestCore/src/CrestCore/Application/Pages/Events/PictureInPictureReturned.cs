using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person pressed the control of a page's Picture in Picture window that
/// returns its video to the page. The engine ends the Picture in Picture and
/// puts the video back in the page itself; the core shows the person the page.
public sealed record PictureInPictureReturned(Guid PageId) : PageEvent(PageId) {
    #region Actions - Pages

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
