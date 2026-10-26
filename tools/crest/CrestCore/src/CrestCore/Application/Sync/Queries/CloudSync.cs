using CrestCore.Application;

namespace CrestCore.Contracts;

/// iCloud sync's status on this device.
public sealed record CloudSync : Query<CloudSyncStatus> {
    #region Variables

    /// The sync control keeps a lock of its own.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override CloudSyncStatus Answer(CrestApp app) {
        int pending = app.CloudSync.PendingUploads();
        lock (app.CloudSync.Gate) return app.CloudSync.Status(pending);
    }

    #endregion
}
