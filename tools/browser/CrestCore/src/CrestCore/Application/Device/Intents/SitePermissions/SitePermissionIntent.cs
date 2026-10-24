using CrestCore.Application;

namespace CrestCore.Contracts;

/// An intent about this device's site permission choices. The device store
/// keeps the persistent session's choices beside the session, never in it,
/// and they never sync; every other Space's choices live in memory until the
/// process ends.
public abstract record SitePermissionIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the device's site permission choices, publishing
    /// each Space it changed to the turn's changes.
    internal abstract void Apply(Device device, DeviceTurn turn);

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.Handle(this, app.DeviceTurn(changes)));

    #endregion
}
