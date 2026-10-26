using CrestCore.Application;

namespace CrestCore.Contracts;

/// Starts the transport's state over, in one save: no saved cursor, no
/// server fields, no full pull and no account decision waiting. With
/// `OverwritesCloud`, this device's copy then overwrites the cloud's until
/// everything it staged has uploaded.
public sealed record ResetCloudTransport(bool OverwritesCloud) : CloudTransportIntent {
    #region Actions - Sync

    internal override IReadOnlyList<Change> Apply(CloudTransportStore transport, Func<bool> journalHoldsUploads) =>
        transport.Changing(() => transport.StartOver(OverwritesCloud));

    #endregion
}
