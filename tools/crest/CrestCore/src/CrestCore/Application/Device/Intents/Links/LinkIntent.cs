using CrestCore.Application;

namespace CrestCore.Contracts;

/// An edit of this device's link preferences, which the device store keeps.
public abstract record LinkIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the device's link preferences, publishing them to
    /// the turn's changes when they changed.
    internal abstract void Apply(Device device, DeviceTurn turn);

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.Handle(this, app.DeviceTurn(changes)));

    #endregion
}
