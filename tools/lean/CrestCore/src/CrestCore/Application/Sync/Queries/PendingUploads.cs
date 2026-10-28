using CrestCore.Application;

namespace CrestCore.Contracts;

/// Which records of the stored session's journal wait to upload. Refused as a
/// `CloudSyncIntent` is, with `NoStoredSession` or `StoredSessionClosed`.
public sealed record PendingUploads : Query<PendingUploadList> {
    #region Variables

    /// It reads the journal, which keeps a lock of its own.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    /// The app asks the stored session the same question before it overwrites the cloud.
    internal override PendingUploadList Answer(CrestApp app) => app.StoredSyncSession().Answer(this);

    #endregion
}
