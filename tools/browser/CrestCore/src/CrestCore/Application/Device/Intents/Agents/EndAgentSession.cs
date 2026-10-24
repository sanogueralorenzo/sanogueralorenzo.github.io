using CrestCore.Application;

namespace CrestCore.Contracts;

/// The agent connected as `SessionId` went, or the person disconnected it: it
/// uses no tab any more.
public sealed record EndAgentSession(Guid SessionId) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseAgentSessions(turn.Changes, sessions => sessions.End(session => session.SessionId == SessionId));

    #endregion
}
