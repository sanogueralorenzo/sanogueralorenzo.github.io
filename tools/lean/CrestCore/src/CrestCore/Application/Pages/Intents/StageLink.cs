using CrestCore.Application;

namespace CrestCore.Contracts;

/// The first load of the page `PageId` names, when it loads `Url`, runs the
/// link the engine of `SourcePageId` staged as `StagedLinkId`. Refused with
/// `StagedLinkElsewhere` when the page is on another engine or profile than
/// the page the link was followed in, or has loaded something already.
public sealed record StageLink(Guid PageId, Guid SourcePageId, Guid StagedLinkId, string Url) : PageIntent {
    #region Actions - Pages

    /// The page's first load runs the link its source page's engine staged, so
    /// the link keeps its referrer, initiator and security. Only a page on the
    /// same engine and profile as its source that has loaded nothing yet can
    /// take the link, whether or not its engine created it already; the
    /// engine checks the link still applies when the page loads.
    internal override void Apply(Pages pages, PageTurn turn) {
        var page = pages.Known(PageId);
        var source = pages.Known(SourcePageId);
        if (!ReferenceEquals(page.Engine, source.Engine) || page.ProfileId != source.ProfileId || !page.AwaitsFirstLoad)
            throw new Rejected(new StagedLinkElsewhere(page.Id, source.Id));
        turn.Issue(page.Engine, new StageNavigation(page.Id, StagedLinkId, Url));
    }

    #endregion
}
