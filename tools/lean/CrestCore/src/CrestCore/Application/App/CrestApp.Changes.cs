using CrestCore.Contracts;

namespace CrestCore.Application;

public sealed partial class CrestApp {
    #region Variables

    /// Changes the core started itself, oldest first, until the host drains them.
    private readonly List<Change> pending = [];
    private readonly Lock pendingGate = new();
    private readonly Lock wakeGate = new();
    private Action? wake;
    private int wakesInFlight;
    private bool turnRequested;
    /// A change arrived in an empty batch while a call held the lock, so the
    /// host is owed a wake once that call lets go, unless it drains first.
    private bool wakeOwed;

    #endregion

    #region Actions - Changes

    /// The changes the core started itself since the last drain, oldest first.
    /// A drain waits for a call that holds the lock, so it never takes part of
    /// what one report or cloud merge published. Engine commands a call from
    /// off the host's thread caused, such as a cloud merge closing a borrowed
    /// workspace's pages, are delivered on the thread that drains, before this
    /// returns.
    public IReadOnlyList<Change> Drain() {
        IReadOnlyList<Change> drained;
        lock (gate) drained = TakePending();
        Deliver();
        return drained;
    }

    /// The changes the core started itself since the last drain, oldest first,
    /// which an intent answers under the lock.
    private IReadOnlyList<Change> TakePending() {
        lock (pendingGate) {
            var drained = pending.ToArray();
            pending.Clear();
            Volatile.Write(ref wakeOwed, false);
            return drained;
        }
    }

    /// Sets the callback that tells the host a drain has something for it, or
    /// removes it with null. The callback carries nothing, runs on whichever
    /// thread published the change, and is never called while the core holds
    /// a lock. When this returns, no earlier callback is still running. A
    /// callback set while changes wait is called at once, so the host hears
    /// the changes the core made before it could.
    public void SetWake(Action? value) {
        lock (wakeGate) wake = value;
        var spinner = new SpinWait();
        while (Volatile.Read(ref wakesInFlight) > 0) spinner.SpinOnce();
        bool waiting;
        lock (pendingGate) waiting = pending.Count > 0;
        if (value is not null && waiting) Wake();
    }

    /// The host finished a turn of its own thread, having drained after a
    /// wake. Work the core queued to follow the host's turn, such as a sync
    /// stage, may start. A drain the host runs inside a turn does not end it.
    public void EndTurn() => device.TurnEnded();

    /// Asks the host for a drain on its next turn, which ends the turn. An
    /// intent that asks waits to wake the host until it releases the lock.
    private void RequestTurn() {
        if (gate.IsHeldByCurrentThread) Volatile.Write(ref turnRequested, true);
        else Wake();
    }

    /// Wakes the host for the turn an intent asked for while it held the lock.
    private void WakeForRequestedTurn() {
        if (Interlocked.Exchange(ref turnRequested, false)) Wake();
    }

    /// Queues a change for the next drain. The host is woken only when the
    /// batch goes from empty to not empty; a drain is already due otherwise.
    /// A change announced while this thread holds the lock owes the wake to
    /// the call that holds it: an intent drains the batch before it returns,
    /// and a report or a cloud intent wakes the host once it lets go. An undrained save gives way
    /// to a newer one and outlasts an older one, which a writer on another
    /// thread can announce after it. A page's newer state replaces its
    /// undrained older one, so a page that changes many times between drains
    /// arrives once, where its latest change falls.
    private void Announce(Change change) {
        bool wakes;
        lock (pendingGate) {
            wakes = pending.Count == 0;
            if (change is Saved saved && pending.Count > 0 && pending[^1] is Saved earlier) {
                if (saved.Revision > earlier.Revision) pending[^1] = saved;
            } else {
                if (change is PageChanged { Page.Id: var pageId })
                    pending.RemoveAll(waiting => waiting is PageChanged older && older.Page.Id == pageId);
                pending.Add(change);
            }
        }
        if (!wakes) return;
        if (gate.IsHeldByCurrentThread) Volatile.Write(ref wakeOwed, true);
        else Wake();
    }

    /// Wakes the host for changes announced while the lock was held and not
    /// drained since.
    private void WakeIfOwed() {
        if (Interlocked.Exchange(ref wakeOwed, false)) Wake();
    }

    private void Wake() {
        Action? target;
        lock (wakeGate) {
            target = wake;
            if (target is null) return;
            Interlocked.Increment(ref wakesInFlight);
        }
        try {
            target();
        } finally {
            Interlocked.Decrement(ref wakesInFlight);
        }
    }

    #endregion
}
