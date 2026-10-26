using CrestCore.Application;

namespace CrestCore.Contracts;

/// Its owner is done with a page. The page is gone at once, and its engine is
/// asked to close what it still holds. `KeepsState` says the owner kept what it
/// needs to bring the page back.
public sealed record ReleasePage(Guid PageId, bool KeepsState) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        var page = pages.Remove(PageId) ?? throw new Rejected(new UnknownPage(PageId));
        turn.Changes.Publish(new PageRemoved(page.Id));
        if (page.Phase.HoldsEnginePage) pages.Close(page, KeepsState, turn.Issue);
    }

    #endregion
}
