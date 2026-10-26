using CrestCore.Application;

namespace CrestCore.Contracts;

/// The retry the core scheduled is due.
public sealed record RetryCloudSync : CloudSyncControlIntent {
    #region Actions - Sync

    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        control.RetryScheduled = false;
        if (!control.IsEnabled || control.Conflict is not null || control.IsRunning) return [];
        return control.SyncNow();
    }

    #endregion
}
