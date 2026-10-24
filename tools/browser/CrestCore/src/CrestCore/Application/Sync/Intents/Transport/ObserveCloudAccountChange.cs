using CrestCore.Application;

namespace CrestCore.Contracts;

/// The iCloud account changed as `Transition` says. A change that always
/// pauses sync waits for the person's decision; a sign-in pauses only while
/// an earlier change still waits for one.
public sealed record ObserveCloudAccountChange(CloudAccountTransition Transition) : CloudTransportIntent {
    #region Actions - Sync

    internal override IReadOnlyList<Change> Apply(CloudTransportStore transport, Func<bool> journalHoldsUploads) =>
        transport.Changing(() => {
            if (Transition.AlwaysPauses && !transport.Record.AwaitsAccountDecision)
                transport.Save(transport.Record with { AwaitsAccountDecision = true }, fields: null);
        });

    #endregion
}
