using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The sync component of a native session. It accepts journals one
/// transaction at a time and stages the session's accepted revisions itself:
/// the session hands it each revision with how that revision stages, and the
/// transport hears `SyncJournalChanged` once the journal holds it. The cloud
/// transport reaches it only through the session's `CloudSyncIntent`s and
/// queries.
public sealed class NativeSyncAuthority {
    #region Variables

    private readonly SyncStager stager;
    private NativeSyncJournal journal;
    private NativeSyncTransaction? pending;
    internal NativeSessionAuthority? Session { get; set; }
    /// The journal this authority accepted last.
    internal NativeSyncJournal Snapshot { get { lock (NativeSessionAuthority.Gate) return journal; } }
    /// How many records the journal holds waiting to upload, which is none
    /// while its session is a disposable seed, as `AnnounceStaged` tells it.
    internal int PendingUploads {
        get {
            lock (NativeSessionAuthority.Gate) return PendingUploadsHeld;
        }
    }
    /// `PendingUploads` for a caller that holds the lock.
    private int PendingUploadsHeld => Session?.IsDisposableSeed == true ? 0 : journal.PendingCount;

    #endregion

    #region Constructors

    public NativeSyncAuthority(NativeSyncJournal initial) {
        journal = initial;
        stager = new(this);
    }

    #endregion

    #region Actions - Transactions

    /// A merge, replacement or overwrite stages the session itself, so the
    /// stages still queued have nothing left to add. Answers the request it
    /// replaced.
    internal SyncStager.Request? Supersede() => stager.Supersede();

    /// Starts a transaction the cloud transport asked for once the one in
    /// progress completes. The caller holds no lock: waiting releases the gate.
    internal NativeSyncTransaction BeginTransaction() => Begin(sequence: null);

    /// Starts a transaction once the one in progress completes. The caller
    /// holds no lock.
    private NativeSyncTransaction Begin(ulong? sequence) {
        lock (NativeSessionAuthority.Gate) {
            while (pending is not null) Monitor.Wait(NativeSessionAuthority.Gate);
            var value = new NativeSyncTransaction(this, sequence, journal);
            pending = value;
            return value;
        }
    }

    internal bool Seal(NativeSyncTransaction value) {
        lock (NativeSessionAuthority.Gate) {
            RequirePending(value);
            if (value.Sequence is { } sequence && !stager.IsCurrent(sequence)) return false;
            value.IsSealed = true;
            return true;
        }
    }

    internal void Commit(NativeSyncTransaction value) {
        lock (NativeSessionAuthority.Gate) {
            RequirePending(value);
            if (!value.IsSealed) throw new InvalidOperationException("A sync transaction commits only once it is sealed.");
            journal = value.Journal;
            pending = null;
            Monitor.PulseAll(NativeSessionAuthority.Gate);
        }
    }

    internal void Cancel(NativeSyncTransaction value) {
        lock (NativeSessionAuthority.Gate) {
            RequirePending(value);
            pending = null;
            Monitor.PulseAll(NativeSessionAuthority.Gate);
        }
        stager.Requeue(value.Superseded);
    }

    private void RequirePending(NativeSyncTransaction value) {
        if (!ReferenceEquals(pending, value)) throw new InvalidOperationException("Only the pending sync transaction completes.");
    }

    #endregion

    #region Actions - Staging

    /// Queues `next`, a revision the session accepted in place of `previous`,
    /// to stage as `staging` says on the worker.
    internal void Queue(SessionState previous, SessionState next, SyncStaging staging) =>
        stager.Queue(previous, next, staging);

    /// Stages `session`, a revision about to be saved in place of `previous`,
    /// for `reason`, replacing whatever is queued; a record a queued edit
    /// removed keeps that edit's reason. Answers the sealed transaction the
    /// revision's reservation saves and publishes; disposing it uncommitted
    /// queues the replaced stage again. Throws `Rejected` naming why it cannot
    /// stage.
    internal NativeSyncTransaction StageWithSave(SessionState previous, SessionState session, SyncDeletionReason reason) {
        var replaced = stager.Supersede();
        var value = Begin(sequence: null);
        value.Superseded = replaced;
        try {
            var removals = (replaced?.Removals ?? SyncRemovals.None).Adding(new(previous, session, reason));
            value.Stage(session, reason, removals.Reasons(reason), StoredSessionCodec.Seconds(DateTimeOffset.UtcNow));
            _ = value.Seal();
            return value;
        } catch (Exception error) {
            value.Dispose();
            throw new Rejected(new SyncStagingRefused(Failure(error)));
        }
    }

    /// Stages one queued request on the worker. Answers false when a newer
    /// stage replaced it, which then settles in its place.
    internal bool StageQueued(SyncStager.Request request) {
        NativeSyncTransaction value;
        try {
            value = Begin(request.Sequence);
        } catch (Exception error) {
            Announce(workspace => new SyncStagingFailed(workspace, Failure(error)));
            return true;
        }
        try {
            value.Stage(request.Session, request.Reason, request.Removals.Reasons(request.Reason),
                StoredSessionCodec.Seconds(DateTimeOffset.UtcNow));
            if (!value.Seal()) {
                value.Dispose();
                return false;
            }
            value.CommitDurably();
        } catch (Exception error) {
            value.Dispose();
            Announce(workspace => new SyncStagingFailed(workspace, Failure(error)));
            return true;
        }
        return true;
    }

    /// Tells the transport what the journal holds now: how many records, and
    /// how many of them wait to upload, which is none while its session is a
    /// disposable seed. Called with no lock held, or holding the lock the host's
    /// intents take.
    internal void AnnounceStaged() {
        int pendingRecords, records;
        lock (NativeSessionAuthority.Gate) (pendingRecords, records) = (PendingUploadsHeld, journal.RecordCount);
        Announce(workspace => new SyncJournalChanged(workspace, pendingRecords, records));
    }

    /// Returns once every stage requested before the call has committed or
    /// failed, without waiting for the host's turn or a coalescing delay.
    public void Flush() => stager.Flush();

    /// Stages whatever is still queued, then stops staging.
    public void Stop() => stager.Stop();

    /// The host of the session's device finished a turn.
    internal void TurnEnded() => stager.TurnEnded();

    /// Asks the host of the session's device for a turn, after which the
    /// stages queued in this one start. Called with no lock held.
    internal void RequestTurn() => Session?.RequestTurn();

    private void Announce(Func<Guid, Change> change) => Session?.Announce(change);

    /// Why a stage failed, for the transport and the person.
    private static SyncStagingFailure Failure(Exception error) => error switch {
        StorageException => SyncStagingFailure.NotSaved,
        BrowserRuleException { Rule.StagingFailure: { } failure } => failure,
        _ => SyncStagingFailure.InvalidSession
    };

    #endregion
}
