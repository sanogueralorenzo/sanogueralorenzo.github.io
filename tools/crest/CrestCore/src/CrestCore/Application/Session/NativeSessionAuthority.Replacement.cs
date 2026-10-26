using CrestCore.Contracts;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    private NativeSyncAuthority? sync;

    /// The file this session keeps, for the saves a sync journal or a
    /// workspace transfer makes on its behalf; null in memory.
    internal SessionStorage? Storage => storage;

    #endregion

    #region Actions - Replacement

    /// Makes `value` this session's sync component and tells the transport
    /// what its journal holds. The first time, it stages the session as it is,
    /// as a launch does.
    internal void AttachSync(NativeSyncAuthority value) {
        SessionState? attached = null;
        lock (Gate) {
            if (!workspaceKind.KeepsFile
                || sync is not null && !ReferenceEquals(sync, value)
                || value.Session is not null && !ReferenceEquals(value.Session, this))
                throw new InvalidOperationException("Only a session that keeps a file syncs, through one sync component of its own.");
            if (sync is null) attached = session;
            sync = value; value.Session = this;
        }
        value.AnnounceStaged();
        if (attached is { DisposableSeedMarker: null }) value.Queue(attached, attached, SyncStaging.Launch);
    }

    /// Ends a reservation, accepting its state when `commit`, and answers the
    /// state it replaced; null when it is cancelled.
    internal SessionState? CompleteReplacement(NativeSessionReplacement value, bool commit) {
        lock (Gate) {
            if (!ReferenceEquals(replacement, value))
                throw new InvalidOperationException("Only the reservation that holds the session completes it.");
            SessionState? previous = null;
            if (commit) {
                value.SyncTransaction?.Commit();
                previous = session;
                session = value.Session; Revision = value.Revision;
                if (value.TransientCompletion is { } completed) completedTransients.Add(completed);
                storage?.Enqueue(session, Revision);
            }
            replacement = null;
            return previous;
        }
    }

    /// Follows the identities the session holds from `previous` to the state
    /// a reservation just committed. The caller holds the gate.
    internal void Committed(SessionState previous) => identities.Accepted(previous, session);

    /// Saves a state reserved from `previous` with the journal it stages, then
    /// publishes it, all before this returns; a failed stage or save leaves
    /// the session, the journal and the file as they were.
    private void SaveStaged(NativeSessionReplacement reserved, SessionState previous, SyncStaging staging) {
        NativeSyncTransaction? staged;
        try {
            staged = StageWithSave(previous, reserved.Session, staging.Reason);
            if (staged is not null) reserved.BindSync(staged);
        } catch {
            reserved.Dispose();
            throw;
        }
        try {
            SaveAndCommit(reserved);
        } catch {
            staged?.Dispose();
            throw;
        }
        staged?.Owner.AnnounceStaged();
    }

    /// The sealed journal `next`, made from `previous`, stages with its save,
    /// or null when no sync is attached or `next` is a disposable seed, which
    /// never syncs.
    internal NativeSyncTransaction? StageWithSave(SessionState previous, SessionState next,
        CrestCore.Contracts.SyncDeletionReason reason) {
        NativeSyncAuthority? target;
        lock (Gate) target = sync;
        return target is null || next.DisposableSeedMarker is not null ? null : target.StageWithSave(previous, next, reason);
    }

    /// Queues the stage of an accepted state, when a sync is attached, the
    /// state holds something `previous` did not and it is no disposable seed.
    private void QueueStage(SessionState previous, SessionState next, SyncStaging? staging) {
        NativeSyncAuthority? target;
        lock (Gate) target = sync;
        if (target is null || staging is null || next.DisposableSeedMarker is not null || next.Equals(previous)) return;
        target.Queue(previous, next, staging);
    }

    /// Saves a reserved state, then publishes it. No lock is held while the
    /// file is written, and other writers stay excluded by the reservation.
    private void SaveAndCommit(NativeSessionReplacement reserved) {
        try {
            storage?.Save(reserved.Session, reserved.Revision, reserved.SyncTransaction?.Journal, reserved.Checkpoint);
        } catch {
            reserved.Dispose();
            throw;
        }
        reserved.Commit();
    }

    /// Reserves `next`, an intent's state, while it is saved: other writers
    /// are refused until it commits or is disposed. What it completes, what
    /// the window that issued it shows next and what it did that the states
    /// cannot tell are published with it. The caller holds the gate.
    private NativeSessionReplacement Reserve(SessionState next, Guid? completes, WindowFollowUp? followUp, SessionTabEvents? events) {
        var checkpoint = new NativeSessionCheckpoint(next);
        _ = checkpoint.Read(NativeSessionCheckpoint.CorePart);
        var reserved = new NativeSessionReplacement(this, next, checked(Revision + 1), checkpoint, completes, followUp, events);
        replacement = reserved;
        return reserved;
    }

    #endregion
}
