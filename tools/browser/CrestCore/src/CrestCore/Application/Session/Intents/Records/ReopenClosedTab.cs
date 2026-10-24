using CrestCore.Application;

namespace CrestCore.Contracts;

/// Reopens the tab the Space archived last, as `RestoreArchivedTab` reopens
/// one, and the window that asked shows it. Refused with `NoArchivedTabs` when
/// the Space keeps none.
public sealed record ReopenClosedTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Reopens the tab the Space archived last, which the issuing window shows.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var newest = space.ArchivedTabs.MaxBy(archived => archived.ArchivedAt) ?? throw new Rejected(new NoArchivedTabs(space.Id));
        return new RestoreArchivedTab(WorkspaceId, WindowId, space.Id, newest.Tab.Id).Edit(workspace, turn);
    }

    #endregion
}
