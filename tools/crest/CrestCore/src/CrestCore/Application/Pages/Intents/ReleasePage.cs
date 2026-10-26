using CrestCore.Application;

namespace CrestCore.Contracts;

/// Its owner is done with a page. The page is gone at once, and its engine is
/// asked to close what it still holds. `KeepsState` says the owner kept what it
/// needs to bring the page back.
public sealed record ReleasePage(Guid PageId, bool KeepsState) : PageIntent {
    #region Actions - Pages

    /// The page is gone at once, so its tab may open another straight away;
    /// the engine closes what it still holds afterwards. A Quick Window's or
    /// Peek's page its owner unloaded, keeping what it needs to bring it back,
    /// leaves what it showed last; releasing it again for good forgets that.
    internal override void Apply(Pages pages, PageTurn turn) {
        if (pages.Remove(PageId) is not { } page) {
            if (!pages.RemembersUnloaded(PageId)) throw new Rejected(new UnknownPage(PageId));
            if (!KeepsState) pages.ForgetUnloaded(PageId);
            return;
        }
        if (page.TabId is null && KeepsState) pages.RememberUnloaded(pages.Transient(page) with { MovesBetweenWindows = false });
        turn.Changes.Publish(new PageRemoved(page.Id));
        if (page.Phase.HoldsEnginePage) pages.Close(page, KeepsState, turn.Issue);
    }

    #endregion
}
