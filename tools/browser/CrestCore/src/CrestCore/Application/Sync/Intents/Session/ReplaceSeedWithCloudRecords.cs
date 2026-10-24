using CrestCore.Application;

namespace CrestCore.Contracts;

/// Replaces the session with the cloud's records, as `ReplaceWithCloudRecords`
/// does, while it is still the disposable seed a first launch made. It changes
/// nothing once the seed is gone.
[MessageLimit(64 * 1024 * 1024)]
public sealed record ReplaceSeedWithCloudRecords(IReadOnlyList<SyncRecord> Records) : CloudSyncIntent {
    #region Actions - Sync

    /// Only a session that is still the disposable seed is replaced.
    internal override IncomingSyncRecords? Apply(NativeSessionAuthority workspace, CloudSyncTurn turn) {
        var records = new IncomingSyncRecords(Records);
        if (workspace.Current.DisposableSeedMarker is not null)
            workspace.Converging(turn.Sync, records, replacing: true, turn.Now, turn.Ids, turn.CommitGate, seedOnly: true);
        return records;
    }

    #endregion
}
