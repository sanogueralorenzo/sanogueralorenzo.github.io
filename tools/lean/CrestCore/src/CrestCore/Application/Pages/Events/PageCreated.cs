using CrestCore.Application;

namespace CrestCore.Contracts;

/// The engine created the page, which is now live.
public sealed record PageCreated(Guid PageId) : PageEvent(PageId) {
    #region Actions - Pages

    /// A page moved to this engine loads the address it showed, and one that
    /// returned to a history entry this engine kept nothing for loads that
    /// entry afresh.
    internal override void Apply(Pages pages, Page page, PageTurn turn) {
        pages.Enter(page, PagePhase.Live, turn.Changes);
        if (page.TakeRehostedLoad() is { } load) turn.Issue(page.Engine, load);
    }

    #endregion
}
