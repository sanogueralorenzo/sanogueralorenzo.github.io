using CrestCore.Application;

namespace CrestCore.Contracts;

/// The transport started for `Attempt` reported `Report`: `Message` carries a
/// failure's words, `RecordCount` counts a batch or the skipped records, and
/// `RequiresAppUpdate` tells whether a newer build wrote records it skipped.
public sealed record CloudTransportReported(long Attempt, CloudTransportReport Report, string? Message, int RecordCount,
    bool RequiresAppUpdate) : CloudSyncControlIntent {
    #region Actions - Sync

    /// What the running transport reported of itself.
    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        if (!control.Current(Attempt)) return [];
        return Report.Settle(control, this);
    }

    #endregion
}
