using CrestCore.Application;

namespace CrestCore.Contracts;

/// What iCloud said of the signed-in account.
public sealed record CloudAccountChecked(long Attempt, CloudAccountState State) : CloudSyncControlIntent {
    #region Actions - Sync

    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        if (!control.Current(Attempt)) return control.Finish();
        control.Account = State;
        if (control.Account != CloudAccountState.Available) {
            control.Phase = CloudSyncPhase.WaitingForAccount;
            return control.Finish();
        }
        return control.SeedIsDisposable() ? [control.Step(CloudSyncStepKind.ReplaceSeed)] : control.AfterSeed(Attempt);
    }

    #endregion
}
