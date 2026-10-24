using CrestCore.Application;

namespace CrestCore.Contracts;

/// Sets when a Space cleans up open tabs, how it blocks content and how long
/// it keeps what it browses. A Space whose cleanup or retention changed is
/// swept under the new rules in the same edit. What it searches with and
/// whether it suggests searches is `SetSpaceSearch`'s.
public sealed record SetBrowsingPreferences(Guid WorkspaceId, Guid SpaceId, CurrentTabCleanup CurrentTabCleanup,
    ContentBlockingPolicy ContentBlocking, DataRetentionPreferences DataRetention)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Sets the Space's browsing preferences apart from its search. A
    /// changed cleanup or retention sweeps the Space under the new rules in
    /// the same edit, which then stages as the records it expired.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var space = workspace.Editable(turn.Basis, SpaceId);
        var before = space.Settings.BrowsingPreferences;
        var preferences = before with {
            CurrentTabCleanup = CurrentTabCleanup,
            ContentBlocking = ContentBlocking,
            DataRetention = DataRetention
        };
        var configured = workspace.Configured(space, space.Settings with { BrowsingPreferences = preferences });
        if (before.CurrentTabCleanup == preferences.CurrentTabCleanup && before.DataRetention == preferences.DataRetention)
            return new(NativeSessionAuthority.Replacing(turn.Basis, configured), SyncStaging.Edit);
        var kept = workspace.TabsCleanupKeeps(turn);
        var swept = workspace.Expired(workspace.CleanedUp(configured, turn.Now, kept), turn.Now);
        return new(NativeSessionAuthority.Replacing(turn.Basis, swept),
            workspace.SameRecords(configured, swept) ? SyncStaging.Edit : SyncStaging.Expiry);
    }

    #endregion
}
