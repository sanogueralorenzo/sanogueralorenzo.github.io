using CrestCore.Application;

namespace CrestCore.Contracts;

/// The agent connected as `SessionId` did `Kind` about `Subject`, which
/// Settings › Agents lists under it while it stays connected.
public sealed record NoteAgentActivity(Guid SessionId, AgentActivityKind Kind, string Subject) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseAgentSessions(turn.Changes, sessions => sessions.Note(SessionId, new AgentActivity(Kind, Subject, turn.Now)));

    #endregion
}
