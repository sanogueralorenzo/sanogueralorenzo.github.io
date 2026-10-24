using CrestCore.Application;

namespace CrestCore.Contracts;

/// The link staged for the page's first load no longer applies, so the page
/// did not load it. A stale link is never retried as a bare address, which
/// would lose where it was followed.
public sealed record StagedLinkUnavailable(Guid PageId) : PageEvent(PageId) {
    #region Actions - Pages

    /// The page stops heading there and shows what it had.
    internal override void Apply(Pages pages, Page page, PageTurn turn) => pages.Update(page, turn.Changes, page.CancelLoad);

    #endregion
}
