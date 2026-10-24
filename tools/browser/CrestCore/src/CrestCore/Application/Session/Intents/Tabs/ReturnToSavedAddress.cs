using CrestCore.Application;

namespace CrestCore.Contracts;

/// Returns a saved or pinned tab to the address it belongs to, which its page
/// then loads. A tab already there changes nothing, and its page may still
/// load it. Refused with `NoSavedAddress` for a tab that belongs nowhere.
public sealed record ReturnToSavedAddress(Guid WorkspaceId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => edited.Tab(TabId).ReturnToSavedAddress());

    #endregion
}
