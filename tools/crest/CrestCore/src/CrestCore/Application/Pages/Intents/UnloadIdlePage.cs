using CrestCore.Application;

namespace CrestCore.Contracts;

/// Unloads a background document after its engine found no unsaved work.
/// A different document, a newly shown page, or new media cancels the unload.
public sealed record UnloadIdlePage(Guid PageId, long Documents, DateTimeOffset HiddenSince) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        pages.Stamp(pages.Clock.Now, turn.Issue);
        if (pages.Hosted(PageId) is not { } page || page.Documents != Documents || page.HiddenSince != HiddenSince
            || !pages.CanAutomaticallyUnload(page, pages.Clock.Now)) return;
        pages.Remove(page.Id);
        turn.Changes.Publish(new PageRemoved(page.Id));
        turn.Changes.Publish(new PageUnloaded(page.Id, page.WorkspaceId, page.TabId!.Value));
        pages.Close(page, keepsState: true, turn.Issue);
    }

    #endregion
}
