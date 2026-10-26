using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person stopped every agent at once: each connection ends, and no
/// agent may use a tab one used again while Crest runs.
public sealed record StopAllAgents : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseAgentSessions(turn.Changes, sessions => sessions.StopAll());

    #endregion
}
