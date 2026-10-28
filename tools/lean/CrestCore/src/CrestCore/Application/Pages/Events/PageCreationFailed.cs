using CrestCore.Application;

namespace CrestCore.Contracts;

/// The engine could not create the page.
public sealed record PageCreationFailed(Guid PageId) : PageEvent(PageId) {
    #region Actions - Pages

    internal override void Apply(Pages pages, Page page, PageTurn turn) => pages.Enter(page, PagePhase.Failed, turn.Changes);

    #endregion
}
