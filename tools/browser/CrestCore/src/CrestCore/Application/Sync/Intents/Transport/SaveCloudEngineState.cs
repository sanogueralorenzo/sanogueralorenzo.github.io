using CrestCore.Application;

namespace CrestCore.Contracts;

/// Keeps the sync engine's saved state, which it hands the transport to
/// resume from.
public sealed record SaveCloudEngineState(byte[] Serialization) : CloudTransportIntent {
    #region Actions - Sync

    internal override IReadOnlyList<Change> Apply(CloudTransportStore transport, Func<bool> journalHoldsUploads) =>
        transport.Changing(() => transport.Save(transport.Record with { EngineState = Serialization }, fields: null));

    #endregion
}
