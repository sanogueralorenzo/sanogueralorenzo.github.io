using CrestCore.Application;

namespace CrestCore.Contracts;

/// Moves a page to the entry `EntryId` names in its back and forward history,
/// as a history menu offers it, leaving any failure the page shows. A page
/// whose history no longer holds the entry, or shows it already, stays.
/// Refused when the page is not open.
public sealed record ShowHistoryEntry(Guid PageId, Guid EntryId) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        var page = pages.Known(PageId);
        if (!page.History.Reaches(EntryId)) return;
        pages.Update(page, turn.Changes, page.LeaveFailure);
        pages.Traverse(page, EntryId, turn);
    }

    #endregion
}
