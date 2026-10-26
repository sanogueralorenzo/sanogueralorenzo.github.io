using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Deletes a folder with all nested folders and tabs. Tabs remain recoverable
/// in the archive; any deleted live collection stays dismissed.
public sealed record DeleteFolder(Guid WorkspaceId, Guid SpaceId, Guid FolderId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var edited = BrowserTabCollection.Restore(space);
        var deleted = edited.DeleteFolder(FolderId, turn.Now);
        var next = edited.Capture(space);
        if (deleted.Any(folder => folder.Source == LiveFolderSource.GitHubPullRequests))
            next = next with { Settings = next.Settings with { IsGitHubFolderDismissed = true } };
        return new(turn.Basis.Replacing(next), SyncStaging.Deletion);
    }

    #endregion
}
