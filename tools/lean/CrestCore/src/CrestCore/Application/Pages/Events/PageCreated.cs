using CrestCore.Application;

namespace CrestCore.Contracts;

/// The engine created the page, which is now live.
public sealed record PageCreated(Guid PageId) : PageEvent(PageId) {
    #region Actions - Pages

    internal override void Apply(Pages pages, Page page, PageTurn turn) {
        pages.Enter(page, PagePhase.Live, turn.Changes);
    }

    #endregion
}
