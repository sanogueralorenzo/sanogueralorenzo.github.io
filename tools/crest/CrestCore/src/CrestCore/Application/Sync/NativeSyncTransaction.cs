using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// One change of a sync journal, which the authority accepts once it commits.
/// Its authority begins one at a time; disposing one uncommitted queues the
/// stage it replaced again.
internal sealed class NativeSyncTransaction : IDisposable {
    #region Variables

    internal NativeSyncAuthority Owner { get; }
    /// The thread that began this transaction, which completes it.
    internal int ThreadId { get; } = Environment.CurrentManagedThreadId;
    /// The queued stage this transaction stages, which commits only while it
    /// is the newest; null for one that always may.
    internal ulong? Sequence { get; }
    /// The queued stage this transaction replaced, queued again if it never
    /// commits.
    internal SyncStager.Request? Superseded { get; set; }
    internal bool IsSealed { get; set; }
    private bool completed, committed;
    internal bool IsReadyToCommit => IsSealed && !completed;
    internal NativeSyncJournal Journal { get; private set; }

    #endregion

    #region Constructors

    internal NativeSyncTransaction(NativeSyncAuthority owner, ulong? sequence, NativeSyncJournal journal) {
        Owner = owner; Sequence = sequence; Journal = journal;
    }

    #endregion

    #region Actions - Sync

    /// Takes the cloud's word that it saved `uploaded`; see
    /// `NativeSyncJournal.Acknowledge`.
    internal void Acknowledge(IReadOnlyList<UploadedRecord> uploaded) {
        Journal = Journal.Acknowledge(uploaded);
        _ = Journal.Read();
    }

    /// Takes `journal`, computed from this transaction's, as the journal it
    /// commits. Throws when the journal outgrows what sync keeps.
    internal void Adopt(NativeSyncJournal journal) {
        Journal = journal;
        _ = Journal.Read();
    }

    /// Stages `session`, deleting each record it lost for the reason `removals`
    /// names for it, else for `reason`, and dating tombstones `now` seconds
    /// since 2001.
    internal void Stage(SessionState session, SyncDeletionReason reason,
        IReadOnlyDictionary<string, SyncDeletionReason> removals, double now) {
        Journal = Journal.Stage(StoredSessionCodec.Encode(session), reason, now, removals);
        _ = Journal.Read();
    }

    internal bool Seal() => Owner.Seal(this);

    internal void Commit() {
        lock (NativeSessionAuthority.Gate) {
            // A paired session replacement may already have published this
            // journal under the same core lock as the browser revision.
            if (committed) return;
            if (completed) throw new InvalidOperationException("A sync transaction completes once.");
            Owner.Commit(this); completed = committed = true;
        }
    }

    /// Publishes a sealed journal after saving it, with the newest accepted
    /// session, when its session keeps a file, then tells the transport what
    /// it holds. A journal that a session replacement already saved and
    /// published is left alone. A failed save leaves the transaction pending
    /// for the caller to release.
    internal void CommitDurably() {
        lock (NativeSessionAuthority.Gate) {
            if (committed) return;
            if (completed || !IsSealed) throw new InvalidOperationException("A sync transaction is saved once it is sealed, and once.");
        }
        Owner.Session?.Storage?.SaveJournal(Journal);
        Commit();
        Owner.AnnounceStaged();
    }

    /// Ends the transaction uncommitted and answers the queued stage it
    /// replaced, which the caller takes over instead of queuing it again.
    internal SyncStager.Request? Abandon() {
        var replaced = Superseded;
        Superseded = null;
        Dispose();
        return replaced;
    }

    public void Dispose() {
        lock (NativeSessionAuthority.Gate) {
            if (completed) return;
            completed = true;
        }
        Owner.Cancel(this);
    }

    #endregion
}
