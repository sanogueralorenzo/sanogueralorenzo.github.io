using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person stopped every agent using `TabId`: none uses it from now on,
/// and none may again while it stays connected.
public sealed record StopAgentTab(Guid TabId) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseAgentSessions(turn.Changes, sessions => sessions.Stop(TabId));

    #endregion
}
