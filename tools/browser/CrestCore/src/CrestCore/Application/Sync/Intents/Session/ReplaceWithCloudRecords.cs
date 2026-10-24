using CrestCore.Application;

namespace CrestCore.Contracts;

/// Replaces the session's synced content and its journal with the cloud's
/// records, as the person chose. Nothing waits to upload afterwards, and an
/// empty cloud leaves one new ordinary Space. What only this device keeps, its
/// app preferences and the Space deletions under way, stays.
[MessageLimit(64 * 1024 * 1024)]
public sealed record ReplaceWithCloudRecords(IReadOnlyList<SyncRecord> Records) : CloudSyncIntent {
    #region Actions - Sync

    internal override IncomingSyncRecords? Apply(NativeSessionAuthority workspace, CloudSyncTurn turn) {
        var records = new IncomingSyncRecords(Records);
        workspace.Converging(turn.Sync, records, replacing: true, turn.Now, turn.Ids, turn.CommitGate);
        return records;
    }

    #endregion
}
