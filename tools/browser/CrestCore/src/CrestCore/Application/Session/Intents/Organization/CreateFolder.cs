using CrestCore.Application;

namespace CrestCore.Contracts;

/// Creates a folder in a Space's saved or open section, or inside `ParentId`,
/// whose section it shares. A blank title names it "New Folder". The tabs
/// `TabIds` names move into it in the same edit, so a folder nobody asked to
/// see empty is never published, and one whose tabs cannot move is never made.
/// A split member brings its split along, unless `LeavesSplits` takes it out.
public sealed record CreateFolder(Guid WorkspaceId, Guid SpaceId, Guid FolderId, TabPlacement Placement, Guid? ParentId,
    string? Title, BrandColor? Color, string? Symbol, IReadOnlyList<Guid> TabIds, bool LeavesSplits) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Creates the folder and files its tabs in one edit.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Creation, edited => {
            edited.AddFolder(FolderId, string.IsNullOrWhiteSpace(Title) ? NativeSessionAuthority.NewFolderTitle : Title,
                Placement, ParentId);
            if (Color is { } color) edited.SetFolderColor(FolderId, color);
            if (Symbol is { } symbol) edited.SetFolderSymbol(FolderId, symbol);
            if (TabIds.Count > 0)
                edited.FileTabs(TabIds, Placement, FolderId, turn.Now, null, null, LeavesSplits);
        });

    #endregion
}
