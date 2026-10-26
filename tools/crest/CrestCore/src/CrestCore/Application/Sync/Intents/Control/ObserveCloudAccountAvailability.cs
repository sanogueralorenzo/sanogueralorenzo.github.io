using CrestCore.Application;

namespace CrestCore.Contracts;

/// iCloud said the signed-in account may have changed: sync starts again
/// against whichever account is signed in now.
public sealed record ObserveCloudAccountAvailability : CloudSyncControlIntent {
    #region Actions - Sync

    /// Starts over against whichever account is signed in now.
    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        var steps = control.CancelRetry();
        control.RetryAttempts = 0;
        control.Attempt++;
        if (control.IsTransportLive) {
            control.IsTransportLive = false;
            steps.Add(control.Step(CloudSyncStepKind.StopTransport));
        }
        control.Conflict = null;
        control.AccountRestartRequested = control.IsRunning;
        if (!control.IsEnabled) return steps;
        control.Phase = CloudSyncPhase.Checking;
        steps.AddRange(control.Start());
        return steps;
    }

    #endregion
}
