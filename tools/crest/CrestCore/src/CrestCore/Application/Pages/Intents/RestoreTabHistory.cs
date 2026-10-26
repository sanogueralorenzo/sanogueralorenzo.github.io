using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record RestoreTabHistory(Guid WorkspaceId, Guid SpaceId, Guid TabId, byte[] Archive) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        var workspace = pages.Device.Workspace(WorkspaceId);
        var space = pages.Hosting(workspace, SpaceId);
        if (workspace.IsPrivateBrowsing || PageHistory.Unarchive(Archive) is not { } history) return;
        pages.KeepArchivedHistory(WorkspaceId, space, TabId, history);
    }

    #endregion
}
