using CrestCore.Application;

namespace CrestCore.Contracts;

/// Moves a page `Offset` entries through its back and forward history: -1
/// goes back, 1 goes forward. Going back from a failed navigation first
/// leaves the failure: a failure over the document the page still shows
/// returns to that document, and one that replaced its document goes back
/// past it. A page whose history has no entry there stays. Refused when the
/// page is not open.
public sealed record StepHistory(Guid PageId, int Offset) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        var page = pages.Known(PageId);
        if (Offset < 0 && page.Live.Failure is { } failure) {
            pages.Update(page, turn.Changes, page.LeaveFailure);
            if (!failure.ReplacedDocument) return;
        }
        if (page.History.Step(Offset) is { } entry) pages.Traverse(page, entry.Id, turn);
    }

    #endregion
}
