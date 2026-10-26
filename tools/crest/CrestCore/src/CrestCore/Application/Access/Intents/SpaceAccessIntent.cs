using CrestCore.Application;

namespace CrestCore.Contracts;

/// An intent about which Spaces this process may show: unlocking one once the
/// device owner authenticates, or locking Spaces again. A grant covers one
/// Space's profile in every workspace that shows it, lives only as long as the
/// process, and is never saved or synced. The platform presents the
/// authentication prompt itself.
public abstract record SpaceAccessIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the grants, publishing the access of every Space
    /// profile it changed.
    internal abstract void Apply(SpaceAccess access, ChangeFeed changes);

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes => app.Access.Handle(this, changes));

    #endregion
}
