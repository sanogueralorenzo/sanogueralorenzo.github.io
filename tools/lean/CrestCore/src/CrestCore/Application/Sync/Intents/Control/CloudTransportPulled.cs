using CrestCore.Application;

namespace CrestCore.Contracts;

/// The transport pulled and merged the `CloudRecords` records the cloud held.
/// `LocalChangesUnsaved` is as `CloudTransportSynced` has it.
public sealed record CloudTransportPulled(long Attempt, int CloudRecords, bool LocalChangesUnsaved) : CloudSyncControlIntent {
    #region Actions - Sync

    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        if (!control.Current(Attempt) || control.AccountRestartRequested) return control.Finish();
        control.ObservedCloud = CloudRecords;
        control.LastFetched = CloudRecords;
        control.Skipped = 0;
        control.RequiresAppUpdate = false;
        var steps = control.RecordSuccess(LocalChangesUnsaved);
        steps.AddRange(control.Finish());
        return steps;
    }

    #endregion
}
