using CrestCore.Application;

namespace CrestCore.Contracts;

/// The back and forward history of page `PageId`, or of the tab's page it was
/// until it closed keeping its state, as its tab's archive keeps it across a
/// relaunch: opaque bytes `RestoreTabHistory` takes back. None for a page the
/// core does not know, one that shows no entry yet, or one in a private
/// workspace.
public sealed record ArchivedPageHistory(Guid PageId) : Query<PageHistoryArchive> {
    #region Actions - Answering

    internal override PageHistoryArchive Answer(CrestApp app) => new(app.Pages.ArchivedHistory(PageId));

    #endregion
}
