using CrestCore.Application;

namespace CrestCore.Contracts;

/// The journal's current record for each of `Records`, as the cloud transport
/// uploads it. Refused as a `CloudSyncIntent` is, with `NoStoredSession` or
/// `StoredSessionClosed`.
public sealed record RecordsToUpload(IReadOnlyList<SyncRecordReference> Records) : Query<UploadBatch> {
    #region Variables

    /// It reads the journal, which keeps a lock of its own.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override UploadBatch Answer(CrestApp app) => Answer(app.StoredSyncSession());

    /// The journal's current record for each reference `query` names, and the
    /// references it no longer holds, which is every one while this session is
    /// a disposable seed. Throws `Rejected` as `AttachedSync` does.
    private UploadBatch Answer(NativeSessionAuthority workspace) {
        var (journal, uploadsNothing) = workspace.SyncedJournal();
        var held = new List<SyncRecord>(Records.Count);
        var gone = new List<SyncRecordReference>();
        foreach (var reference in Records) {
            if (uploadsNothing || !journal.Holds(reference)) gone.Add(reference);
            else if (journal.Uploading(reference) is { } record) held.Add(record);
        }
        return new(held, gone);
    }

    #endregion
}
