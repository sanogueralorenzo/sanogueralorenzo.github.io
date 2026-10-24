using CrestCore.Application;

namespace CrestCore.Contracts;

/// The merge `MergeId` ended, having taken its records when `Succeeded`. A
/// failed merge leaves a full pull required; a full snapshot taken with no
/// merge failing meanwhile recovers every earlier one. The full pull stays
/// required while another merge is under way. A merge this device never
/// began is `UnknownCloudMerge`.
public sealed record FinishCloudMerge(long MergeId, bool Succeeded, bool FullSnapshot) : CloudTransportIntent {
    #region Actions - Sync

    /// Ends a merge: a failed one leaves the full pull required; a full
    /// snapshot taken with no merge failing since it began recovers every
    /// earlier failure. The pull stays required while another merge is under
    /// way. The caller holds the lock.
    private void Finish(CloudTransportStore transport) {
        if (!transport.Merges.Remove(MergeId, out int failuresBefore)) throw new Rejected(new UnknownCloudMerge(MergeId));
        if (!Succeeded) {
            transport.FailedMerges++;
            transport.NeedsRecovery = true;
            transport.Save(transport.Record with { RequiresFullPull = true }, fields: null);
            return;
        }
        if (FullSnapshot && transport.FailedMerges == failuresBefore) transport.NeedsRecovery = false;
        try {
            transport.Save(transport.Record with { RequiresFullPull = transport.NeedsRecovery || transport.Merges.Count > 0 },
                fields: null);
        } catch (Rejected) {
            transport.NeedsRecovery = true;
            throw;
        }
    }

    #endregion

    #region Actions - Routing

    internal override IReadOnlyList<Change> Apply(CloudTransportStore transport, Func<bool> journalHoldsUploads) =>
        transport.Changing(() => Finish(transport));

    #endregion
}
