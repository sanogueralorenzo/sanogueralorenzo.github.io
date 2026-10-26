using CrestCore.Application;

namespace CrestCore.Contracts;

/// Merges records the cloud sent into the session and its journal. The
/// session's edits are staged first; each record the journal holds already
/// resolves against the one that arrived, field by field where the fields carry
/// their own clocks; the session is rebuilt from the reconciled records,
/// repaired, swept for retention and staged again. A Space tombstone for an
/// explicit deletion begins deleting that Space on this device. A tab or
/// archive that arrives in another Space than the journal holds it in moved
/// there, and the winning version decides where it stays; any other record the
/// journal holds in another Space is refused.
[MessageLimit(64 * 1024 * 1024)]
public sealed record MergeSyncRecords(IReadOnlyList<SyncRecord> Records) : CloudSyncIntent {
    #region Actions - Sync

    internal override IncomingSyncRecords? Apply(NativeSessionAuthority workspace, CloudSyncTurn turn) {
        var records = new IncomingSyncRecords(Records);
        if (!records.IsEmpty) workspace.Converging(turn.Sync, records, replacing: false, turn.Now, turn.Ids, turn.CommitGate);
        return records;
    }

    #endregion
}
