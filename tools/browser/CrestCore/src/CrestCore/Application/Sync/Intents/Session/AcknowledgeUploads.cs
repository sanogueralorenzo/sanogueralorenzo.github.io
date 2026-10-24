using CrestCore.Application;

namespace CrestCore.Contracts;

/// The cloud saved `Records`. Each that the journal still holds at exactly the
/// version the cloud saved no longer waits to upload; one the journal wrote
/// again since, or no longer holds, is left as it is. The journal is saved
/// before this returns and publishes `SyncJournalChanged`; the session does not
/// change.
public sealed record AcknowledgeUploads(IReadOnlyList<UploadedRecord> Records) : CloudSyncIntent {
    #region Actions - Sync

    internal override IncomingSyncRecords? Apply(NativeSessionAuthority workspace, CloudSyncTurn turn) {
        NativeSessionAuthority.Acknowledging(turn.Sync, Records);
        return null;
    }

    #endregion
}
