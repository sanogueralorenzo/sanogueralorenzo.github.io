using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person let the agent connected as `SessionId` open windows without
/// asking each time, until it disconnects.
public sealed record AllowAgentWindows(Guid SessionId) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseAgentSessions(turn.Changes, sessions => sessions.AllowWindows(SessionId));

    #endregion
}
