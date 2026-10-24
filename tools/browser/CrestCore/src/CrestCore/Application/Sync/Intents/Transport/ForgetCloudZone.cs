using CrestCore.Application;

namespace CrestCore.Contracts;

/// The cloud's zone of Crest's records is gone, as `Loss` says: every
/// record's server fields go with it, and so does the engine's saved state
/// unless the loss restores the zone from this device's records.
public sealed record ForgetCloudZone(CloudZoneLoss Loss) : CloudTransportIntent {
    #region Actions - Sync

    internal override IReadOnlyList<Change> Apply(CloudTransportStore transport, Func<bool> journalHoldsUploads) =>
        transport.Changing(() => transport.Save(Loss.RestoresLocalRecords ? transport.Record : transport.Record with { EngineState = null },
            CloudFieldWrite.Cleared));

    #endregion
}
