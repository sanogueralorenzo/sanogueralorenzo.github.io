using CrestCore.Application;

namespace CrestCore.Contracts;

/// How this device's content compares with the `CloudRecords` records the
/// cloud held.
public sealed record CloudContentCompared(long Attempt, int CloudRecords, CloudContentComparison Comparison) : CloudSyncControlIntent {
    #region Actions - Sync

    /// Content that differs pauses for the person; a device with nothing takes
    /// the cloud's; otherwise the transport starts over.
    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        if (!control.Current(Attempt)) return control.Finish();
        control.ObservedCloud = CloudRecords;
        var comparison = Comparison;
        if (comparison.DeviceRecords > 0 && !comparison.Matches) {
            control.Conflict = comparison;
            control.Phase = CloudSyncPhase.NeedsReconciliation;
            return control.Finish();
        }
        if (comparison.DeviceRecords == 0 && comparison.CloudRecords > 0) return [control.Step(CloudSyncStepKind.TakeCloudContent)];
        return control.ResetThenStart(Attempt, overwritesCloud: false);
    }

    #endregion
}
