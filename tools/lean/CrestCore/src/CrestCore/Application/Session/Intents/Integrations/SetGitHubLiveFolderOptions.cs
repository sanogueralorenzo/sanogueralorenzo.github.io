using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record SetGitHubLiveFolderOptions(Guid WorkspaceId, Guid SpaceId, Guid ProfileId, Guid FolderId,
    GitHubLiveFolderOptions Options) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequirePreferenceOwner();
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (space.ProfileId != ProfileId || !Options.IsValid
            || space.Folders.FirstOrDefault(folder => folder.Id == FolderId)?.Source != LiveFolderSource.GitHubPullRequests)
            throw new Rejected(new InvalidLiveFolder(SpaceId));
        return workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit,
            edited => edited.SetGitHubLiveFolderOptions(FolderId, Options.Normalized()));
    }

    #endregion
}
