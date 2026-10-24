using CrestCore.Application;

namespace CrestCore.Contracts;

/// No page will load the link the engine of `SourcePageId` staged as
/// `StagedLinkId`, so its engine forgets it. A source page the core no longer
/// hosts took its staged links with it.
public sealed record DiscardStagedLink(Guid SourcePageId, Guid StagedLinkId) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        if (pages.Hosted(SourcePageId) is { } source) turn.Issue(source.Engine, new DropStagedLink(StagedLinkId));
    }

    #endregion
}
