using CrestCore.Application;

namespace CrestCore.Contracts;

/// Prepares to quit: every page this device hosts may go, and the person
/// agrees to stop the downloads still in progress. Refused with
/// `SpaceDeletionUnderway` while the engines are erasing the profile data of
/// a Space being deleted, which a quit would interrupt. A deletion that is
/// not erasing holds nothing back; the next launch resumes it.
public sealed record PrepareToQuit(Guid RequestId) : CloseIntent(RequestId) {
    #region Actions - Closing

    internal override void Apply(ClosePreparations preparations, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        var deleting = preparations.Device.SpacesBeingDeleted(preparations.DataDeletions.Erasing);
        if (deleting.Count > 0) throw new Rejected(new SpaceDeletionUnderway(deleting));
        preparations.Start(RequestId, quits: true, preparations.Pages.All.Select(page => page.Id), changes, issue);
    }

    #endregion
}
