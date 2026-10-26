using CrestCore.Application;

namespace CrestCore.Contracts;

/// An intent about the browsing data one workspace's session holds: its
/// Spaces' history, archive, tabs, folders and splits. The core stamps the
/// edit with its own clock, and the session publishes what the edit changed.
/// An intent that changes nothing publishes nothing.
public abstract record SessionIntent(Guid WorkspaceId) : Intent {
    #region Variables

    /// Whether the session the edit leaves is checked whole rather than
    /// against the one it edits, as an import that brings Spaces whole is.
    internal virtual bool ValidatesWholeSession => false;

    #endregion

    #region Abstract Methods

    /// The edit the intent makes to the session the turn reads, or null for
    /// one that has nothing to do, such as a sweep the last one covers. The
    /// workspace holds its gate, and validates the edit before it commits it.
    internal abstract SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn);

    #endregion

    #region Actions - Session

    /// Moves what the intent names out of this workspace into another, when
    /// it does, and answers whether it did; without `commits` it only checks
    /// the move. Only a tab moving to a window of another workspace does.
    internal virtual bool MovedAcross(NativeSessionAuthority workspace, DateTimeOffset now, bool commits) => false;

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes => Commit(app, changes));

    /// Commits the intent to the session of the workspace it names. An intent
    /// that asks more of the device first or afterwards adds to it.
    internal virtual void Commit(CrestApp app, ChangeFeed changes) =>
        app.Device.Workspace(WorkspaceId).Handle(this, app.Clock.Now, app.Ids, app.Pages);

    #endregion
}
