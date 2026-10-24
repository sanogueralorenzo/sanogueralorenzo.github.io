using CrestCore.Application;

namespace CrestCore.Contracts;

/// The copy the person chose was applied over the `CloudRecords` records the
/// cloud held.
public sealed record CloudCopyApplied(long Attempt, bool UsesCloud, int CloudRecords) : CloudSyncControlIntent {
    #region Actions - Sync

    /// The transport starts over from the chosen copy: this device's
    /// overwrites the cloud's until everything it staged has uploaded.
    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        if (!control.Current(Attempt)) return control.Finish();
        control.ObservedCloud = CloudRecords;
        if (!control.Reset(overwritesCloud: !UsesCloud, Attempt)) return control.Finish();
        control.IsTransportLive = false;
        control.Conflict = null;
        return control.StartTransport();
    }

    #endregion
}
