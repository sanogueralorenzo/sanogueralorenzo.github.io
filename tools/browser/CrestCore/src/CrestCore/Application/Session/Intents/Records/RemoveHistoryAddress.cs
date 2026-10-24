using CrestCore.Application;

namespace CrestCore.Contracts;

/// Removes the history entry for one address from a Space. The address is
/// compared the way history records it, without its fragment, so an address
/// history never records removes nothing.
public sealed record RemoveHistoryAddress(Guid WorkspaceId, Guid SpaceId, string Address) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var address = new WebAddress(Address).Normalized;
        var remaining = workspace.WithoutHistory(space, entry => address is not null && entry.Url == address);
        return new(NativeSessionAuthority.Replacing(turn.Basis, remaining), SyncStaging.Deletion);
    }

    #endregion
}
