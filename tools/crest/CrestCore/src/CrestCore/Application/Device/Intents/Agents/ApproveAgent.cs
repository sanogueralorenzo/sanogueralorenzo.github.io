using CrestCore.Application;

namespace CrestCore.Contracts;

/// Trusts `Agent` from now on, after the person allowed it. Refused with
/// `InvalidAgent` for an identity that names no program or a name with nothing
/// to show, and with `AgentsFull` past the most the device keeps.
public sealed record ApproveAgent(ApprovedAgent Agent) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseAgents(turn.Changes, preferences => preferences.Approving(Agent));

    #endregion
}
