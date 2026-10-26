using CrestCore.Application;

namespace CrestCore.Contracts;

/// Gives tab `TabId` of `SpaceId` the back and forward history its archive
/// kept across a relaunch, as `ArchivedPageHistory` answered it, for the next
/// page the tab opens: that page opens on the engine of the entry the history
/// shows, and going back or forward reaches every engine the tab went
/// through. A tab that has a page, or holds a history it kept since, keeps
/// that; a private workspace keeps none; an archive this build cannot read
/// changes nothing. Refused when the workspace or Space is not there, or the
/// Space is locked or being deleted.
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
