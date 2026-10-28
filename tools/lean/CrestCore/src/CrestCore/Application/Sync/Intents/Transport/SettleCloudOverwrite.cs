using CrestCore.Application;

namespace CrestCore.Contracts;

/// Ends this device's overwrite of the cloud once the journal of the session
/// the core keeps in its file holds nothing waiting to upload, after every
/// stage queued before it settled. Refused with `NoStoredSession` or
/// `StoredSessionClosed` as a `CloudSyncIntent` is.
public sealed record SettleCloudOverwrite : CloudTransportIntent {
    #region Actions - Sync

    internal override IReadOnlyList<Change> Apply(CloudTransportStore transport, Func<bool> journalHoldsUploads) {
        // The journal is read before the store's lock is taken.
        bool holdsUploads = journalHoldsUploads();
        return transport.Changing(() => {
            if (transport.Record.OverwritesCloud && !holdsUploads)
                transport.Save(transport.Record with { OverwritesCloud = false }, fields: null);
        });
    }

    #endregion
}
