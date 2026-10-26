using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether this build holds the entitlement for Crest's container.
public sealed record CloudEntitlementChecked(long Attempt, bool Granted) : CloudSyncControlIntent {
    #region Actions - Sync

    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        if (!control.Current(Attempt)) return control.Finish();
        if (!Granted) {
            control.Phase = CloudSyncPhase.Failed;
            control.Problem = CloudSyncProblem.EntitlementMissing;
            control.FailureMessage = null;
            control.Account = CloudAccountState.CouldNotDetermine;
            return control.Finish();
        }
        control.Phase = CloudSyncPhase.Checking;
        control.ClearFailure();
        control.LastAttemptAt = control.Clock.Now;
        return [control.Step(CloudSyncStepKind.CheckAccount)];
    }

    #endregion
}
