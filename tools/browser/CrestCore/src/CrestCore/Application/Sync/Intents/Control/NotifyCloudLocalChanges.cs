using CrestCore.Application;

namespace CrestCore.Contracts;

/// This device staged local changes for the transport to upload.
public sealed record NotifyCloudLocalChanges : CloudSyncControlIntent {
    #region Actions - Sync

    /// A live transport that no conflict holds hears of them.
    internal override List<CloudSyncStep> Steps(CloudSyncControl control) =>
        control.IsEnabled && control.Conflict is null && control.IsTransportLive ? [control.Step(CloudSyncStepKind.NotifyTransport)] : [];

    #endregion
}
