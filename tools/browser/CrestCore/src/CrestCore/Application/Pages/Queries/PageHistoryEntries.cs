using CrestCore.Application;

namespace CrestCore.Contracts;

/// The entries a page can go back and forward to, nearest first, for its
/// history menus. A page the core does not host has none.
public sealed record PageHistoryEntries(Guid PageId) : Query<PageHistoryList> {
    #region Actions - Answering

    internal override PageHistoryList Answer(CrestApp app) =>
        app.Pages.Hosted(PageId)?.History is { } history ? new(history.Back, history.Forward) : new([], []);

    #endregion
}
