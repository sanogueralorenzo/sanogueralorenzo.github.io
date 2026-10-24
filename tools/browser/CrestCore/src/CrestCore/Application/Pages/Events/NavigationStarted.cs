using CrestCore.Application;

namespace CrestCore.Contracts;

/// A page began navigating to `Url`: a load that will replace its document,
/// or, when `SameDocument`, a move within the document it shows, such as
/// `history.pushState` or a fragment. Nothing is recorded until the
/// navigation finishes.
public sealed record NavigationStarted(Guid PageId, string Url, bool SameDocument) : PageEvent(PageId) {
    #region Actions - Pages

    /// A navigation to another document of a site chosen for another
    /// registered engine moves the page there, which loads it instead. A page
    /// another page opened stays on its opener's engine: moving it would cut
    /// it off from the page that opened it, as a sign-in window's redirects
    /// would. A navigation that replays the page's history stays on the
    /// engine that holds it: going back or forward is not a new navigation.
    internal override void Apply(Pages pages, Page page, PageTurn turn) {
        if (!SameDocument && !page.OpenedByPage && !page.History.Replays(Url) && pages.Shown(page) is { } space && pages.Chosen(space, Url) is { } chosen
            && !ReferenceEquals(chosen, page.Engine))
            pages.Rehost(page, chosen, Url, RehostReason.SiteChoice, turn);
    }

    #endregion
}
