using CrestCore.Application;

namespace CrestCore.Contracts;

/// The transport started.
public sealed record CloudTransportStarted(long Attempt) : CloudSyncControlIntent {
    #region Actions - Sync

    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        var steps = control.Current(Attempt)
            ? [] : new List<CloudSyncStep> { CloudSyncControl.Step(CloudSyncStepKind.DiscardStartedTransport, Attempt) };
        steps.AddRange(control.Finish());
        return steps;
    }

    #endregion
}
