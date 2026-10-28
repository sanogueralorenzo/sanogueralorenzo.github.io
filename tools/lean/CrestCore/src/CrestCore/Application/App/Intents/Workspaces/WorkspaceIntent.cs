using CrestCore.Application;

namespace CrestCore.Contracts;

/// An intent about which workspaces this device's windows may show: opening
/// one, borrowing a Space into one and closing one. The core gives each
/// workspace its identity and publishes `WorkspaceOpened` with its whole
/// session, which every later change to that session names.
public abstract record WorkspaceIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the app's workspaces. What it changes joins the
    /// pending batch, in the order it happened. The caller holds the lock.
    internal abstract void Apply(CrestApp app);

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(_ => app.Handle(this));

    #endregion
}
