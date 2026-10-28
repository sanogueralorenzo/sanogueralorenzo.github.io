using CrestCore.Application;

namespace CrestCore.Contracts;

/// A page began navigating to `Url`: a load that will replace its document,
/// or, when `SameDocument`, a move within the document it shows, such as
/// `history.pushState` or a fragment. Nothing is recorded until the
/// navigation finishes.
public sealed record NavigationStarted(Guid PageId, string Url, bool SameDocument) : PageEvent(PageId) {
    #region Actions - Pages

    internal override void Apply(Pages pages, Page page, PageTurn turn) { }

    #endregion
}
