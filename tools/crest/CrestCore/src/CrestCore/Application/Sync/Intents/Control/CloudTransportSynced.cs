using CrestCore.Application;

namespace CrestCore.Contracts;

/// The transport fetched and sent without failing. `LocalChangesUnsaved`
/// tells whether the core could not stage or save this device's latest
/// edits meanwhile.
public sealed record CloudTransportSynced(long Attempt, bool LocalChangesUnsaved) : CloudSyncControlIntent {
    #region Actions - Sync

    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        if (!control.Current(Attempt) || control.AccountRestartRequested) return control.Finish();
        if (control.Conflict is not null) {
            control.Phase = CloudSyncPhase.NeedsReconciliation;
            return control.Finish();
        }
        var steps = control.RecordSuccess(LocalChangesUnsaved);
        steps.AddRange(control.Finish());
        return steps;
    }

    #endregion
}
