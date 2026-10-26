using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person left the notice of a page's failed navigation for the page
/// behind it. Refused when the page is not open.
public sealed record LeavePageFailure(Guid PageId) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        var page = pages.Known(PageId);
        pages.Update(page, turn.Changes, page.LeaveFailure);
    }

    #endregion
}
