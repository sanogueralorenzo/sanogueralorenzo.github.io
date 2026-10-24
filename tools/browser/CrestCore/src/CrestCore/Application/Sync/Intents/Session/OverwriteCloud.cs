using CrestCore.Application;

namespace CrestCore.Contracts;

/// Prepares the journal to overwrite the cloud with this device's session, as
/// the person chose: each record the cloud holds is superseded by one written
/// above it, and every record waits to upload. The session does not change.
[MessageLimit(64 * 1024 * 1024)]
public sealed record OverwriteCloud(IReadOnlyList<SyncRecord> Records) : CloudSyncIntent {
    #region Actions - Sync

    internal override IncomingSyncRecords? Apply(NativeSessionAuthority workspace, CloudSyncTurn turn) {
        var records = new IncomingSyncRecords(Records);
        workspace.Overwriting(turn.Sync, records, turn.Now);
        return records;
    }

    #endregion
}
