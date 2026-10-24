using CrestCore.Application;

namespace CrestCore.Contracts;

/// Applies every Space's retention: open tabs unused for longer than the
/// Space's cleanup lifetime move to its archive, and history and archive
/// entries older than the Space keeps them are removed. A tab a window shows,
/// or a saved window will show, stays open, and so does a tab whose page
/// runs media. Locked Spaces are swept too, since a sweep reveals nothing;
/// Spaces being deleted are not.
///
/// Every window of a workspace asks for sweeps, so a sweep less than a minute
/// after the last one does nothing, unless a Space's retention changed since.
public sealed record SweepExpiredRecords(Guid WorkspaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Cleans up and applies retention in every Space not being deleted, or
    /// nothing when the last sweep covers this one.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        if (workspace.LastSweep?.Covers(turn.Now, turn.Basis) == true) return null;
        var kept = workspace.TabsCleanupKeeps(turn);
        var swept = workspace.EditableSpaces(turn.Basis, maintains: true)
            .Select(space => workspace.Expired(workspace.CleanedUp(space, turn.Now, kept), turn.Now)).ToArray();
        return new(NativeSessionAuthority.Replacing(turn.Basis, swept), SyncStaging.Expiry,
            Sweep: new(turn.Now, NativeSessionAuthority.SpaceRetention.Of(turn.Basis)));
    }

    #endregion
}
