using CrestCore.Application;

namespace CrestCore.Contracts;

/// An edit of what a Space's palette remembers on this device, which the
/// device store keeps for the persistent session's Spaces and never syncs.
public abstract record PaletteIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on what the device's palettes remember.
    internal abstract void Apply(Device device, DeviceTurn turn);

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.Handle(this, app.DeviceTurn(changes)));

    #endregion
}
