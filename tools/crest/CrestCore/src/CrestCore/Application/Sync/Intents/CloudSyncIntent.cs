using CrestCore.Application;

namespace CrestCore.Contracts;

/// An intent from the cloud transport about the session the core keeps in its
/// file, which alone syncs. Refused with `NoStoredSession` when the core keeps
/// no file, its file holds no session, or that session is not open yet, which
/// the transport never meets since it starts after `OpenWorkspace`; and with
/// `StoredSessionClosed` once that session closed. Each is saved with its
/// journal before it returns; a save that fails is `SaveFailed` and changes
/// nothing. A locked Space never refuses one: sync converges in the background.
///
/// The transport sends one from its own thread, never the host's: the core
/// computes it there, outside its lock, and takes the lock only to commit it.
/// What it changed reaches the host through the next drain, as one batch after
/// the wake, never in its answer, which carries only the intent's receipts.
///
/// Records the core cannot take are `InvalidSyncRecords`, and a journal that
/// cannot record the result is `SyncStagingRefused`; either changes nothing.
public abstract record CloudSyncIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the stored session and its journal, and answers the
    /// records it read, whose receipt the transport hears, or null when it
    /// read none.
    internal abstract IncomingSyncRecords? Apply(NativeSessionAuthority workspace, CloudSyncTurn turn);

    #endregion

    #region Actions - Routing

    /// Runs on the transport's thread, outside the app's turns; see `CrestApp.Handle`.
    internal sealed override IReadOnlyList<Change> Route(CrestApp app) => app.Handle(this);

    #endregion
}
