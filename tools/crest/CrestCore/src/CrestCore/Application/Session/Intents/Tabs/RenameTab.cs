using CrestCore.Application;

namespace CrestCore.Contracts;

/// Names a tab, over whatever its page calls itself. A blank or null title
/// hands the tab back to its page's title. Refused with `InvalidName` for a
/// name too long to keep.
public sealed record RenameTab(Guid WorkspaceId, Guid SpaceId, Guid TabId, string? Title) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => edited.Tab(TabId).Rename(Title, turn.Now));

    #endregion
}
