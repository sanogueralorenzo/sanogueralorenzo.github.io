using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person confirmed a pull of everything iCloud holds. A pull merges the
/// cloud's content; it never takes either side in place of the other.
public sealed record RequestCloudPull : CloudSyncControlIntent {
    #region Actions - Sync

    /// Pulls a full snapshot through the running transport.
    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        if (!control.IsEnabled || control.Conflict is not null || control.IsRunning || control.Account != CloudAccountState.Available
            || !control.IsTransportLive)
            return [];
        control.IsRunning = true;
        control.LastAttemptAt = control.Clock.Now;
        control.Phase = CloudSyncPhase.Syncing;
        return [control.Step(CloudSyncStepKind.PullTransport)];
    }

    #endregion
}
