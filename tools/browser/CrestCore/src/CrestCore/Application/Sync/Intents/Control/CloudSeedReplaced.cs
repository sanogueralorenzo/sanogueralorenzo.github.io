using CrestCore.Application;

namespace CrestCore.Contracts;

/// The disposable seed was replaced with the `CloudRecords` records the
/// cloud held.
public sealed record CloudSeedReplaced(long Attempt, int CloudRecords) : CloudSyncControlIntent {
    #region Actions - Sync

    /// The first launch took the cloud's content in place of its seed, so the
    /// transport starts over from it.
    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        control.ObservedCloud = CloudRecords;
        if (!control.Reset(overwritesCloud: false, Attempt)) return control.Finish();
        return control.AfterSeed(Attempt);
    }

    #endregion
}
