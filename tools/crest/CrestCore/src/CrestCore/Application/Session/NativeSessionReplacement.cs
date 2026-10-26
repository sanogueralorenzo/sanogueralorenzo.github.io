using CrestCore.Contracts;

namespace CrestCore.Application;

/// A validated state reserved while it is saved. Other writers are refused
/// until it is committed or disposed; disposing an uncommitted reservation
/// leaves the session as it was.
internal sealed class NativeSessionReplacement : IDisposable {
    #region Variables

    private readonly NativeSessionAuthority owner;
    private bool completed;
    internal SessionState Session { get; }
    /// The revision storage saves the state as.
    internal ulong Revision { get; }
    internal Guid? TransientCompletion { get; }
    /// What the command chose for the window that issued it to show next.
    internal WindowFollowUp? FollowUp { get; }
    /// What the command did that the states cannot tell.
    internal SessionTabEvents Events { get; }
    internal NativeSessionCheckpoint Checkpoint { get; }
    internal NativeSyncTransaction? SyncTransaction { get; private set; }

    #endregion

    #region Constructors

    internal NativeSessionReplacement(NativeSessionAuthority owner, SessionState session,
        ulong revision, NativeSessionCheckpoint checkpoint, Guid? transientCompletion = null,
        WindowFollowUp? followUp = null, SessionTabEvents? events = null) {
        this.owner = owner; Session = session; Revision = revision; Checkpoint = checkpoint;
        TransientCompletion = transientCompletion;
        FollowUp = followUp;
        Events = events ?? SessionTabEvents.None;
    }

    #endregion

    #region Actions - Replacement

    internal void BindSync(NativeSyncTransaction value) {
        lock (NativeSessionAuthority.Gate) {
            if (completed || SyncTransaction is not null || !value.IsReadyToCommit || !ReferenceEquals(value.Owner.Session, owner))
                throw new InvalidOperationException("A reservation binds one sealed journal of its own session.");
            SyncTransaction = value;
        }
    }

    /// Accepts the reserved state, then tells the device.
    internal void Commit() => owner.Published(Complete(), Session, FollowUp, Events);

    /// Accepts the reserved state and answers the one it replaced. The caller
    /// tells the device once it holds no lock.
    internal SessionState Complete() {
        lock (NativeSessionAuthority.Gate) {
            if (completed) throw new InvalidOperationException("A reservation completes once.");
            var previous = owner.CompleteReplacement(this, true)!;
            completed = true;
            owner.Committed(previous);
            return previous;
        }
    }

    /// Leaves the session as it was.
    public void Dispose() {
        lock (NativeSessionAuthority.Gate) {
            if (completed) return;
            owner.CompleteReplacement(this, false);
            completed = true;
        }
    }

    #endregion
}
