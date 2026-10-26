using CrestCore.Application;

namespace CrestCore.Contracts;

/// How the stored session's journal compares with `Cloud`, every record the
/// cloud holds, which the transport asks before it syncs with an account it has
/// not synced with yet. Refused as a `CloudSyncIntent` is, with
/// `NoStoredSession` or `StoredSessionClosed`.
[MessageLimit(64 * 1024 * 1024)]
public sealed record CloudComparison(IReadOnlyList<SyncRecord> Cloud) : Query<CloudContentComparison> {
    #region Variables

    /// It reads the journal, which keeps a lock of its own.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override CloudContentComparison Answer(CrestApp app) => Answer(app.StoredSyncSession());

    /// How this session's journal compares with the cloud's records, holding
    /// nothing while this session is a disposable seed. Throws `Rejected` as
    /// `AttachedSync` does, and with `InvalidSyncRecords` for a cloud record
    /// whose body cannot be read.
    private CloudContentComparison Answer(NativeSessionAuthority workspace) {
        var (journal, holdsNothing) = workspace.SyncedJournal();
        return journal.Comparing(Cloud, holdsNothing);
    }

    #endregion
}
