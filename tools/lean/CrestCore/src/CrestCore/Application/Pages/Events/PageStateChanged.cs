using CrestCore.Application;

namespace CrestCore.Contracts;

/// What a page's engine shows changed. A binding reports a page's latest
/// snapshot at most once per turn, and only when it differs from the last one
/// it reported.
public sealed record PageStateChanged(Guid PageId, PageSnapshot Snapshot) : PageEvent(PageId) {
    #region Actions - Pages

    /// A title the page gave its recorded document since names the page's
    /// tab, and its visit while the page settles. A page whose Space this
    /// process may not show, which reports a video floating in Picture in
    /// Picture, is asked at once to end it.
    internal override void Apply(Pages pages, Page page, PageTurn turn) {
        pages.Update(page, turn.Changes, () => page.Show(Snapshot));
        var now = pages.Clock.Now;
        if (page.Retitle(now) is var (url, title, visit) && (page.TabId is not null || visit))
            pages.Edit(page, new TitleRecord(page.Id, page.SpaceId, now, page.TabId, url, title, visit), turn.Changes);
        pages.EndPictureInPicture(page, shownAgain: false, turn.Issue);
    }

    #endregion
}
