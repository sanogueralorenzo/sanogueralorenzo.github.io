using CrestCore.Application;

namespace CrestCore.Contracts;

/// Keeps the server fields of `Updated`, replacing what was kept of each, and
/// forgets those of `Removed`.
[MessageLimit(64 * 1024 * 1024)]
public sealed record RecordCloudFields(IReadOnlyList<CloudRecordFields> Updated, IReadOnlyList<string> Removed)
    : CloudTransportIntent {
    #region Actions - Sync

    internal override IReadOnlyList<Change> Apply(CloudTransportStore transport, Func<bool> journalHoldsUploads) =>
        transport.Changing(() => transport.Save(next: null, new CloudFieldWrite(Clearing: false, Updated, Removed)));

    #endregion
}
