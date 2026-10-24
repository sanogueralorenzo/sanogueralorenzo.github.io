using CrestCore.Application;

namespace CrestCore.Contracts;

/// An edit of this device's search catalog, which the device store keeps and
/// never syncs.
public abstract record SearchCatalogIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the device's catalog, publishing it when it changed.
    internal abstract void Apply(Device device, DeviceTurn turn);

    #endregion

    #region Actions - Routing

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes => app.Device.Handle(this, app.DeviceTurn(changes)));

    #endregion
}
