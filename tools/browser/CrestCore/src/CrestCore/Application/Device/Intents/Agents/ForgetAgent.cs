using CrestCore.Application;

namespace CrestCore.Contracts;

/// Stops trusting the agent `Identity` names and disconnects it, so the person
/// is asked again the next time it asks for Crest.
public sealed record ForgetAgent(AgentIdentity Identity) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseAgents(turn.Changes, preferences => preferences.Forgetting(Identity));

    #endregion
}
