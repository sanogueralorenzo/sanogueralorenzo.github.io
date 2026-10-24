using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person chose which copy to keep after the account changed: the
/// cloud's in place of this device's when `UsesCloud`, or this device's over
/// the cloud's.
public sealed record ChooseCloudCopy(bool UsesCloud) : CloudSyncControlIntent {
    #region Actions - Sync

    /// Applies the copy the person chose, then starts the transport over it.
    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        if (!control.IsEnabled || control.Conflict is null || !control.CanReachCloud || control.IsRunning) return [];
        control.IsRunning = true;
        control.Attempt++;
        control.Phase = CloudSyncPhase.Syncing;
        control.LastAttemptAt = control.Clock.Now;
        return [new CloudSyncStep(CloudSyncStepKind.ApplyChosenCopy, control.Attempt, UsesCloud)];
    }

    #endregion
}
