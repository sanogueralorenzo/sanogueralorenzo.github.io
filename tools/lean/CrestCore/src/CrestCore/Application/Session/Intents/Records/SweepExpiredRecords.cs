using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record SweepExpiredRecords(Guid WorkspaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Applies record retention in every Space not being deleted, or
    /// nothing when the last sweep covers this one.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        if (workspace.LastSweep?.Covers(turn.Now, turn.Basis) == true) return null;
        var swept = workspace.EditableSpaces(turn.Basis)
            .Select(space => workspace.Expired(space, turn.Now)).ToArray();
        return new(turn.Basis.Replacing(swept), SyncStaging.Expiry,
            Sweep: new(turn.Now, NativeSessionAuthority.SpaceRetention.Of(turn.Basis)));
    }

    #endregion
}
