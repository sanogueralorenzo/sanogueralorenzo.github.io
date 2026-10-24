using CrestCore.Application;

namespace CrestCore.Contracts;

/// Moves setup on this device along. Each publishes setup as it leaves it in
/// `SetupFlowChanged`. One is refused with `NoSetup` while setup is not open,
/// and one that changes what setup works on with `SetupBusy` while it reads or
/// imports.
public abstract record SetupFlowIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the setup open on the device, publishing the flow it
    /// leaves.
    internal abstract void Apply(Device device, DeviceTurn turn);

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.Handle(this, app.DeviceTurn(changes)));

    #endregion
}
