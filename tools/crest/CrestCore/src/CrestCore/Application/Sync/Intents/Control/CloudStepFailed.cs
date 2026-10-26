using CrestCore.Application;

namespace CrestCore.Contracts;

/// The step `Step` failed, as `Message` says. `ObservedCloudRecords` counts
/// the records the cloud held when a snapshot loaded before the failure.
public sealed record CloudStepFailed(long Attempt, CloudSyncStepKind Step, string Message, int? ObservedCloudRecords)
    : CloudSyncControlIntent {
    #region Actions - Sync

    /// A failed step fails the start, sync, pull or choice it belonged to.
    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        if (Step == CloudSyncStepKind.StartTransport && control.Current(Attempt)) control.IsTransportLive = false;
        if (!control.Current(Attempt)) return control.Finish();
        if (ObservedCloudRecords is { } observed) control.ObservedCloud = observed;
        control.Fail(Message);
        return control.Finish();
    }

    #endregion
}
