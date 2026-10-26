using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Reconciles an authenticated collection into a real saved folder in one edit.
/// A failed fetch never sends this intent. Renames, navigations, tab identities,
/// folder disclosure and manually dismissed items survive subsequent refreshes.
public sealed record RefreshLiveFolder(Guid WorkspaceId, Guid SpaceId, Guid ProfileId, Guid FolderId,
    LiveFolderSource Source, IReadOnlyList<LiveFolderTab> Tabs, GitHubLiveFolderOptions? ExpectedOptions = null) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequirePreferenceOwner();
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (space.Settings.IsGitHubFolderDismissed || space.ProfileId != ProfileId || Tabs.Count > 100 || Tabs.Any(tab => !Source.Accepts(tab.Url)
            || string.IsNullOrWhiteSpace(tab.Title) || tab.Title.Length > 512)) throw new Rejected(new InvalidLiveFolder(SpaceId));
        var options = ExpectedOptions ?? GitHubLiveFolderOptions.Default;
        var currentOptions = space.Folders.FirstOrDefault(folder => folder.Id == FolderId)?.GitHubOptions
            ?? GitHubLiveFolderOptions.Default;
        if (!options.IsValid || !currentOptions.Matches(options.Normalized())) throw new Rejected(new InvalidLiveFolder(SpaceId));
        var dismissed = space.ArchivedTabs.Where(item => item.Reason == ArchiveReason.Deleted)
            .Select(item => item.Tab.SavedUrl ?? item.Tab.Url).ToHashSet(StringComparer.Ordinal);
        var items = Tabs.DistinctBy(tab => tab.Url, StringComparer.Ordinal).Where(tab => !dismissed.Contains(tab.Url))
            .Select(tab => workspace.NewTab(Guid.NewGuid(), new TabContent(tab.Url, null, tab.Title), TabPlacement.Saved, turn.Now)).ToArray();
        return workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Creation,
            edited => edited.RefreshLiveFolder(FolderId, Source, items, turn.Now));
    }

    #endregion
}
