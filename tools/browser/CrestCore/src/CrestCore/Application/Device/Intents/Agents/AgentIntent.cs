using CrestCore.Application;

namespace CrestCore.Contracts;

/// An edit of this device's agent preferences, or of the agents connected now.
/// Only a device that offers agents runs one; any other refuses it with
/// `AgentsUnavailable`.
public abstract record AgentIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the device, publishing what it changed to the turn's
    /// changes.
    internal abstract void Apply(Device device, DeviceTurn turn);

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.Handle(this, app.DeviceTurn(changes)));

    #endregion
}
