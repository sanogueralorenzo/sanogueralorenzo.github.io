using CrestCore.Application;

namespace CrestCore.Contracts;

/// Prepares to close the windows `WindowIds` names, asking each page that goes
/// with them. A page its workspace's other windows keep, as the Mac's windows
/// over the person's own Spaces keep theirs, has nothing to ask; the private
/// window's pages and a torn-off tab's window's go with it. A workspace whose
/// pages go with their windows goes once its last window closes, so closing
/// that window asks every page of it, whichever window hosts it, as the
/// private window's Quick Windows.
public sealed record PrepareToCloseWindows(Guid RequestId, IReadOnlyList<Guid> WindowIds) : CloseIntent(RequestId) {
    #region Actions - Closing

    internal override void Apply(ClosePreparations preparations, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        var windows = WindowIds.ToHashSet();
        var pages = preparations.Pages;
        var ending = preparations.Device.EndingWorkspaces(windows);
        var closing = pages.All.Where(page => windows.Contains(page.WindowId) && pages.GoesWithItsWindow(page)
            || ending.Contains(page.WorkspaceId)).Select(page => page.Id);
        preparations.Start(RequestId, quits: false, closing, changes, issue);
    }

    #endregion
}
