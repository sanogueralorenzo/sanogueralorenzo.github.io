using CrestCore.Contracts;

namespace CrestCore.Application;

/// Stages a session's accepted revisions in its sync journal on a worker of its
/// own, from each revision's immutable state, so the UI never waits for a
/// projection.
///
/// A queued stage waits for the host to finish the turn that queued it and
/// for its urgency's delay, then stages the newest queued session with the
/// newest edit's reason. So the edits one turn of the host makes stage once,
/// however many there are, and each record one of them removed is deleted for
/// the reason of the edit that removed it. A stage requested later replaces
/// one that has not committed, taking over its edits; one that finds itself
/// replaced when it seals is dropped, and the newer one stages instead. A
/// stage that runs outside the worker, because its revision is saved with the
/// journal or because a merge stages the local session itself, supersedes
/// whatever is queued.
///
/// Its state is guarded by the session gate, which the worker also waits on.
internal sealed class SyncStager {
    #region Types

    /// One requested stage: the session to stage, the reason its removals are
    /// deleted for unless an earlier edit removed them, the edits it covers,
    /// when its delay ends, the host turn it was queued in and its place among
    /// requests. `Delay` is the shortest delay among the edits it covers and
    /// `Since` when the first of them was queued.
    internal sealed record Request(SessionState Session, SyncDeletionReason Reason, SyncRemovals Removals, DateTimeOffset Due,
        ulong Turn, ulong Sequence, TimeSpan Delay, DateTimeOffset Since) {
        #region Actions - Supersession

        /// The request that covers the edits of `earlier`, which a stage
        /// outside the worker replaced, and of `later`, which it replaced
        /// after: `later` taking over `earlier`'s edits, or whichever is
        /// not null.
        public static Request? Covering(Request? earlier, Request? later) =>
            earlier is null ? later : later is null ? earlier : later with {
                Removals = earlier.Removals.Joining(later.Removals),
                Due = earlier.Due < later.Due ? earlier.Due : later.Due,
                Delay = earlier.Delay < later.Delay ? earlier.Delay : later.Delay,
                Since = earlier.Since < later.Since ? earlier.Since : later.Since
            };

        #endregion
    }

    #endregion

    #region Variables

    private readonly NativeSyncAuthority owner;
    private Thread? worker;
    /// The newest request not yet staged.
    private Request? queued;
    /// The request the worker is staging, whose edits a newer request takes
    /// over in case its stage is dropped.
    private Request? staging;
    /// The newest request or supersession; only a stage for it may commit.
    private ulong requested;
    /// Every request up to this one has staged, failed, or been superseded by
    /// one that did.
    private ulong settled;
    /// Requests up to this one stage without waiting.
    private ulong expedited;
    /// How many turns the host has finished.
    private ulong turns;
    private bool stopped;

    #endregion

    #region Constructors

    public SyncStager(NativeSyncAuthority owner) => this.owner = owner;

    #endregion

    #region Actions - Requests

    /// Queues `next`, which an edit made from `previous`, to stage with
    /// `edit`'s reason once the host's turn ends and its urgency's delay passes
    /// without a newer request. An edit still waiting with a shorter delay
    /// keeps it, so a frequent, patient edit never holds back an urgent one,
    /// and a patient edit waits no longer than its urgency's maximum.
    public void Queue(SessionState previous, SessionState next, SyncStaging edit) {
        lock (NativeSessionAuthority.Gate) {
            if (stopped) return;
            requested++;
            var removals = Pending.Adding(new(previous, next, edit.Reason));
            var now = DateTimeOffset.UtcNow;
            var waiting = queued ?? staging;
            var delay = waiting is { } earlier && earlier.Delay < edit.Urgency.Delay ? earlier.Delay : edit.Urgency.Delay;
            var since = waiting?.Since ?? now;
            var due = now + delay;
            if (edit.Urgency.MaximumWait is { } maximum && since + maximum < due) due = since + maximum;
            queued = new(next, edit.Reason, removals, due, turns, requested, delay, since);
            worker ??= Start();
            Monitor.PulseAll(NativeSessionAuthority.Gate);
        }
        owner.RequestTurn();
    }

    /// A stage that runs outside the worker now covers every queued edit.
    /// Answers the request it replaced, whose edits it takes over and which
    /// `Requeue` restores if that stage never commits.
    public Request? Supersede() {
        lock (NativeSessionAuthority.Gate) {
            var replaced = queued ?? staging;
            queued = null;
            requested++;
            settled = requested;
            Monitor.PulseAll(NativeSessionAuthority.Gate);
            return replaced;
        }
    }

    /// Queues again a request whose superseding stage did not commit, unless a
    /// newer request has taken its place.
    public void Requeue(Request? replaced) {
        if (replaced is null) return;
        lock (NativeSessionAuthority.Gate) {
            if (stopped || queued is not null) return;
            requested++;
            queued = replaced with { Turn = turns, Sequence = requested };
            worker ??= Start();
            Monitor.PulseAll(NativeSessionAuthority.Gate);
        }
        owner.RequestTurn();
    }

    /// Whether a stage for `sequence` may still commit. The caller holds the
    /// session gate.
    public bool IsCurrent(ulong sequence) => sequence == requested;

    /// The edits no stage has committed yet: those of the queued request, or
    /// of the one being staged. The caller holds the session gate.
    private SyncRemovals Pending => (queued ?? staging)?.Removals ?? SyncRemovals.None;

    /// The host finished a turn, so the stages it queued may start.
    public void TurnEnded() {
        lock (NativeSessionAuthority.Gate) {
            turns++;
            Monitor.PulseAll(NativeSessionAuthority.Gate);
        }
    }

    /// Returns once every stage requested before the call has settled, with
    /// no turn or delay left to wait for.
    public void Flush() {
        lock (NativeSessionAuthority.Gate) {
            var target = requested;
            expedited = Math.Max(expedited, target);
            Monitor.PulseAll(NativeSessionAuthority.Gate);
            while (settled < target && worker is not null) Monitor.Wait(NativeSessionAuthority.Gate);
        }
    }

    /// Stages whatever is still queued without waiting, then stops the worker.
    /// Later requests are ignored.
    public void Stop() {
        Thread? running;
        lock (NativeSessionAuthority.Gate) {
            stopped = true;
            expedited = requested;
            running = worker;
            Monitor.PulseAll(NativeSessionAuthority.Gate);
        }
        if (running is not null && running != Thread.CurrentThread) running.Join();
    }

    #endregion

    #region Actions - Worker

    private Thread Start() {
        var thread = new Thread(Run) { IsBackground = true, Name = "Crest sync staging" };
        thread.Start();
        return thread;
    }

    private void Run() {
        while (Next() is { } request) {
            bool settles = owner.StageQueued(request);
            lock (NativeSessionAuthority.Gate) {
                staging = null;
                if (settles) settled = Math.Max(settled, request.Sequence);
                Monitor.PulseAll(NativeSessionAuthority.Gate);
            }
        }
    }

    /// Waits for the newest queued request to be due and takes it, or answers
    /// null once nothing is queued, and the worker ends until the next request.
    private Request? Next() {
        lock (NativeSessionAuthority.Gate) {
            while (queued is { } next) {
                if (stopped || next.Sequence <= expedited) return Take();
                if (turns > next.Turn) {
                    var wait = next.Due - DateTimeOffset.UtcNow;
                    if (wait <= TimeSpan.Zero) return Take();
                    Monitor.Wait(NativeSessionAuthority.Gate, wait);
                } else {
                    Monitor.Wait(NativeSessionAuthority.Gate);
                }
            }
            worker = null;
            Monitor.PulseAll(NativeSessionAuthority.Gate);
            return null;
        }

        Request Take() {
            var next = queued!;
            queued = null;
            staging = next;
            return next;
        }
    }

    #endregion
}
