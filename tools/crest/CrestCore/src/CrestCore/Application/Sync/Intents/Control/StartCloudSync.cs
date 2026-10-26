using CrestCore.Application;

namespace CrestCore.Contracts;

/// Brings sync up against the account that is signed in now, unless it is
/// off, already starting, or running.
public sealed record StartCloudSync : CloudSyncControlIntent {
    #region Actions - Sync

    internal override List<CloudSyncStep> Steps(CloudSyncControl control) => control.Start();

    #endregion
}
