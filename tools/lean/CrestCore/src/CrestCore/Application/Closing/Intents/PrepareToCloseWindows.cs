using CrestCore.Application;

namespace CrestCore.Contracts;

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
