using CrestCore.Application;

namespace CrestCore.Contracts;

/// Starts, edits or ends the manual setup this device holds. Each publishes
/// the setup as it leaves it in `SetupDraftChanged`. An edit is refused with
/// `NoManualSetup` while no setup is in progress.
public abstract record SetupDraftIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the manual setup the device holds, publishing the
    /// setup it leaves.
    internal abstract void Apply(Device device, DeviceTurn turn);

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.Handle(this, app.DeviceTurn(changes)));

    #endregion
}
