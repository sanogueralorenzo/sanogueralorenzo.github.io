using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person turned sync on or off. Turning it off stops the transport and
/// starts its state over, except while an account decision waits: turning
/// sync off is not an answer to whether this is the same iCloud account.
public sealed record SetCloudSyncEnabled(bool IsEnabled) : CloudSyncControlIntent {
    #region Actions - Sync

    /// Turning sync on starts it, once a start under way ends; turning it off
    /// drops the transport and starts its state over, keeping an account
    /// decision that waits.
    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        if (control.IsEnabled == IsEnabled) return [];
        control.IsEnabled = IsEnabled;
        if (control.IsEnabled) {
            if (control.IsRunning) {
                control.AccountRestartRequested = true;
                return [];
            }
            return control.Start();
        }
        control.Attempt++;
        var steps = control.CancelRetry();
        if (control.IsTransportLive) {
            control.IsTransportLive = false;
            steps.Add(control.Step(CloudSyncStepKind.StopTransport));
        }
        control.Conflict = null;
        control.AccountRestartRequested = false;
        control.Phase = CloudSyncPhase.Disabled;
        control.ClearFailure();
        try {
            control.Transport.ResetUnlessAwaitingDecision();
        } catch (Rejected) {
            // The next start starts over from what was kept.
        }
        return steps;
    }

    #endregion
}
