using CrestCore.Application;

namespace CrestCore.Contracts;

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
