using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Explicitly adds GitHub again after dismissal, without reconciling or
/// clearing existing tabs. Automatic creation uses an authenticated refresh.
public sealed record EnableGitHubLiveFolder(Guid WorkspaceId, Guid SpaceId, Guid ProfileId, Guid FolderId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequirePreferenceOwner();
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (space.ProfileId != ProfileId) throw new Rejected(new InvalidLiveFolder(SpaceId));
        var existing = space.Folders.FirstOrDefault(folder => folder.Source == LiveFolderSource.GitHubPullRequests);
        var edited = BrowserTabCollection.Restore(space);
        edited.EnableLiveFolder(existing?.Id ?? FolderId, LiveFolderSource.GitHubPullRequests);
        var next = edited.Capture(space);
        // Adding a dismissed collection starts its list afresh. Its deleted
        // pages stay recoverable without suppressing the new collection.
        if (space.Settings.IsGitHubFolderDismissed)
            next = next with {
                ArchivedTabs = [.. next.ArchivedTabs.Select(item => item.Reason == ArchiveReason.Deleted
                && LiveFolderSource.GitHubPullRequests.Accepts(item.Tab.SavedUrl ?? item.Tab.Url)
                ? item with { Reason = ArchiveReason.Closed } : item)]
            };
        next = next with { Settings = next.Settings with { IsGitHubFolderDismissed = false } };
        return new(turn.Basis.Replacing(next), SyncStaging.Creation);
    }

    #endregion
}
