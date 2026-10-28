using CrestCore.Application;

namespace CrestCore.Contracts;

/// The restart an account change asked for is due.
public sealed record RestartCloudSyncAfterAccountChange : CloudSyncControlIntent {
    #region Actions - Sync

    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        if (!control.AccountRestartRequested || control.IsRunning) return [];
        control.AccountRestartRequested = false;
        return control.Start();
    }

    #endregion
}
