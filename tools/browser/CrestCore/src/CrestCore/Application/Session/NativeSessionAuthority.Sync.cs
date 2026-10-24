using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

#region Types

/// What one intent of the cloud transport needs: the sync component the
/// session stages into, the time it runs at, where the identities repair gives
/// come from, and the lock the host's intents take, which a merge or
/// replacement commits holding.
internal sealed record CloudSyncTurn(NativeSyncAuthority Sync, DateTimeOffset Now, IIdSource Ids, Lock CommitGate);

#endregion

public sealed partial class NativeSessionAuthority {
    #region Static Variables

    /// How often a merge computed outside the lock is computed again when the
    /// session moved meanwhile, before it computes holding the lock.
    private const int ConvergenceAttempts = 3;

    #endregion

    #region Types

    /// What converging with the cloud's records makes: the journal, the session
    /// and the tabs repair gave a new identity, each with the tab whose image
    /// it wears.
    private sealed record Convergence(NativeSyncJournal Journal, SessionState Session, SessionTabEvents Events);

    #endregion

    #region Variables

    /// Whether this session is the disposable seed a first launch made, which
    /// never syncs.
    internal bool IsDisposableSeed {
        get {
            lock (Gate) return session.DisposableSeedMarker is not null;
        }
    }

    #endregion

    #region Actions - Cloud sync

    /// Runs one intent from the cloud transport at `now`, drawing the
    /// identities repair gives from `ids`, and saves what it changed before it
    /// returns; see `CloudSyncIntent`. It runs on the transport's thread,
    /// holding no lock. A merge or replacement commits holding `commitGate`,
    /// the lock the host's intents take, so what it publishes joins their
    /// order whole; an intent about the journal alone never takes it. Answers
    /// the intent's receipts: `SyncRecordsSkipped` when it left records out.
    /// Throws `Rejected`.
    internal IReadOnlyList<Change> Handle(CloudSyncIntent intent, DateTimeOffset now, IIdSource ids, Lock commitGate) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(ids);
        var records = intent.Apply(this, new CloudSyncTurn(AttachedSync(), now, ids, commitGate));
        return records?.Receipt ?? [];
    }

    /// The sync component this session stages into. Throws `Rejected` with
    /// `StoredSessionClosed` once the session closed, and `NoStoredSession`
    /// before a sync is attached.
    private NativeSyncAuthority AttachedSync() {
        lock (Gate) {
            if (released) throw new Rejected(new StoredSessionClosed());
            return sync ?? throw new Rejected(new NoStoredSession());
        }
    }

    /// Merges `records` into the session and its journal, or replaces both
    /// with them. The journal transaction begins before any lock is taken:
    /// waiting for one in progress releases the gate. The result is computed
    /// holding no lock, from the session as it was, and committed holding
    /// `commitGate`, then the gate, when the session has not moved meanwhile;
    /// otherwise it is computed again, a few times, then holding both. The
    /// commit reserves, saves the session and its journal, and publishes both
    /// before `commitGate` is released. The stages still queued are superseded
    /// before each computation, and a merge deletes each record their edits
    /// removed for the reason of the edit that removed it; a transaction that
    /// never commits queues them again.
    internal void Converging(NativeSyncAuthority sync, IncomingSyncRecords records, bool replacing, DateTimeOffset now,
        IIdSource ids, Lock commitGate, bool seedOnly = false) {
        var superseded = sync.Supersede();
        var transaction = sync.BeginTransaction();
        transaction.Superseded = superseded;
        NativeSessionReplacement? reserved = null;
        try {
            if (!replacing) records.RequireSameSpaces(transaction.Journal);
            for (int attempt = 0; ; attempt++) {
                Convergence? computed = null;
                ulong revision = 0;
                if (attempt < ConvergenceAttempts) {
                    SessionState basis;
                    lock (Gate) {
                        Supersede(sync, transaction);
                        (basis, revision) = (IntentBasis(), Revision);
                    }
                    if (seedOnly && basis.DisposableSeedMarker is null) {
                        transaction.Dispose();
                        return;
                    }
                    computed = Converge(transaction, basis, records, replacing, now, ids);
                }
                lock (commitGate) {
                    lock (Gate) {
                        if (computed is null) {
                            Supersede(sync, transaction);
                            var basis = IntentBasis();
                            if (seedOnly && basis.DisposableSeedMarker is null) {
                                transaction.Dispose();
                                return;
                            }
                            computed = Converge(transaction, basis, records, replacing, now, ids);
                        } else if (Revision != revision) {
                            continue;
                        }
                        reserved = Reserving(transaction, computed);
                    }
                    Committing(sync, transaction, reserved);
                    return;
                }
            }
        } catch (Exception error) when (reserved is null) {
            transaction.Dispose();
            throw Refusal(error);
        }
    }

    /// Saves `reserved` with the journal `transaction` holds, then publishes
    /// both. A failed save leaves the session, the journal and the file as they
    /// were. The caller holds the lock the host's intents take.
    private void Committing(NativeSyncAuthority sync, NativeSyncTransaction transaction, NativeSessionReplacement reserved) {
        try {
            reserved.BindSync(transaction);
            SaveAndCommit(reserved);
        } catch (Exception error) {
            reserved.Dispose();
            transaction.Dispose();
            throw Refusal(error);
        }
        sync.AnnounceStaged();
    }

    /// Makes `transaction` cover the stages queued since it last superseded
    /// them. The caller holds the gate.
    private static void Supersede(NativeSyncAuthority sync, NativeSyncTransaction transaction) =>
        transaction.Superseded = SyncStager.Request.Covering(transaction.Superseded, sync.Supersede());

    /// The journal and session `records` make of `basis` and the journal
    /// `transaction` holds, at `now`, with the tabs repair gave a new identity.
    private Convergence Converge(NativeSyncTransaction transaction, SessionState basis, IncomingSyncRecords records,
        bool replacing, DateTimeOffset now, IIdSource ids) {
        var journal = transaction.Journal;
        var emptySpace = SpaceTemplate.Ordinary.Make(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid, number: 1, now);
        var removals = (transaction.Superseded?.Removals ?? SyncRemovals.None).Reasons(SyncDeletionReason.Superseded);
        var result = NativeSyncSessionTransition.Prepare(journal, basis, records.Batch(), replacing, now, emptySpace, Access, ids, removals);
        _ = result.Journal.Read();
        return new(result.Journal, result.Session, new(Copies(basis, result.Session, result.Origins), Favicon: null));
    }

    /// The tabs repair gave a new identity that the session held before, each
    /// with the tab it was.
    private static IReadOnlyList<SessionTabCopy> Copies(SessionState basis, SessionState next, IReadOnlyList<NativeSessionMaintenance.TabOrigin> origins) {
        var held = basis.Spaces.SelectMany(space => space.Tabs.Select(tab => (space.Id, tab.Id))).ToHashSet();
        var copies = new List<SessionTabCopy>();
        foreach (var origin in origins) {
            var space = next.Spaces[origin.SpaceIndex];
            var copy = space.Tabs[origin.TabIndex].Id;
            var source = (origin.SourceSpaceId, origin.SourceTabId);
            if (copy != source.Item2 && held.Contains(source)) copies.Add(new(source.Item2, copy));
        }
        return copies;
    }

    /// Reserves `computed` while it is saved with its journal, which
    /// `transaction` takes. The caller holds the gate, and binds the two.
    private NativeSessionReplacement Reserving(NativeSyncTransaction transaction, Convergence computed) {
        Validate(computed.Session);
        ValidateBorrowedSession(computed.Session);
        transaction.Adopt(computed.Journal);
        _ = transaction.Seal();
        return Reserve(computed.Session, completes: null, followUp: null, computed.Events);
    }

    /// Rebases the journal above `records`, the cloud's, from the session as
    /// it is, so every record waits to upload, and saves the journal. The
    /// session does not change. The stages still queued are superseded first,
    /// and each record their edits removed is deleted for the reason of the
    /// edit that removed it; a transaction that never commits queues them
    /// again.
    internal void Overwriting(NativeSyncAuthority sync, IncomingSyncRecords records, DateTimeOffset now) {
        var superseded = sync.Supersede();
        var transaction = sync.BeginTransaction();
        transaction.Superseded = superseded;
        try {
            SessionState basis;
            lock (Gate) {
                Supersede(sync, transaction);
                basis = IntentBasis();
            }
            var removals = (transaction.Superseded?.Removals ?? SyncRemovals.None).Reasons(SyncDeletionReason.Superseded);
            transaction.Adopt(transaction.Journal.Overwrite(StoredSessionCodec.Encode(basis), records.Batch(),
                StoredSessionCodec.Seconds(now), removals));
            _ = transaction.Seal();
            transaction.CommitDurably();
        } catch (Exception error) {
            transaction.Dispose();
            throw Refusal(error);
        }
    }

    /// Takes the cloud's word that it saved `uploaded`, and saves the journal
    /// before it returns. The session does not change.
    internal static void Acknowledging(NativeSyncAuthority sync, IReadOnlyList<UploadedRecord> uploaded) {
        ArgumentNullException.ThrowIfNull(uploaded);
        var transaction = sync.BeginTransaction();
        try {
            transaction.Acknowledge(uploaded);
            _ = transaction.Seal();
            transaction.CommitDurably();
        } catch (Exception error) {
            transaction.Dispose();
            throw Refusal(error);
        }
    }

    /// The rejection `error`, a failure to take the cloud's records, stands
    /// for. A save that failed is `SaveFailed`; a rule that names a flaw of
    /// the records is `InvalidSyncRecords` with that flaw; a rule that names
    /// only how a stage fails, such as a journal that cannot record the
    /// result, is `SyncStagingRefused`; and a failure no rule names is
    /// `InvalidSyncRecords` with `Unexpected`, never a fault the host sees.
    private static Rejected Refusal(Exception error) => error switch {
#if CREST_CROSS_CHECKS
        // A cross-check that disagreed is a fault in the core that tests must see.
        System.Diagnostics.UnreachableException => throw error,
#endif
        Rejected { Rejection: InvalidSession { Flaw: SessionFlaw.SharedProfile } } =>
            new(new InvalidSyncRecords(SyncRecordFlaw.SharedProfile, null)),
        Rejected { Rejection: InvalidSession } => new(new InvalidSyncRecords(SyncRecordFlaw.Unexpected, null)),
        Rejected rejected => rejected,
        StorageException storage => new(new SaveFailed(storage.Reason)),
        SyncRecordsFlawedException flawed => new(new InvalidSyncRecords(flawed.Flaw, flawed.Subject)),
        BrowserRuleException { Rule.RecordFlaw: { } flaw } => new(new InvalidSyncRecords(flaw, null)),
        BrowserRuleException { Rule.StagingFailure: { } failure } => new(new SyncStagingRefused(failure)),
        JsonException or KeyNotFoundException or FormatException => new(new InvalidSyncRecords(SyncRecordFlaw.MalformedRecord, null)),
        _ => new(new InvalidSyncRecords(SyncRecordFlaw.Unexpected, null))
    };

    #endregion

    #region Actions - Uploads

    /// The records of this session's journal that wait to upload; none while
    /// it is a disposable seed. Throws `Rejected` as `AttachedSync` does.
    internal PendingUploadList Answer(PendingUploads query) {
        ArgumentNullException.ThrowIfNull(query);
        var (journal, uploadsNothing) = SyncedJournal();
        return new(uploadsNothing ? [] : journal.PendingReferences());
    }

    /// The journal this session's sync accepted last, and whether this session
    /// is a disposable seed, which uploads nothing. Throws `Rejected` as
    /// `AttachedSync` does.
    internal (NativeSyncJournal Journal, bool UploadsNothing) SyncedJournal() {
        lock (Gate) return (AttachedSync().Snapshot, session.DisposableSeedMarker is not null);
    }

    #endregion
}
