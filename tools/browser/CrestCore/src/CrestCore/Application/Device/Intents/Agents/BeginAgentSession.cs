using CrestCore.Application;

namespace CrestCore.Contracts;

/// An agent the person allowed connected as `SessionId`, which Crest shows as
/// `Name` until it names itself. Refused with `AgentsOff` while agents are off,
/// `AgentNotApproved` for an agent the person did not allow, and
/// `AgentSessionsFull` past the most connected at once.
public sealed record BeginAgentSession(Guid SessionId, AgentIdentity Identity, string Name) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.BeginAgentSession(turn.Changes, SessionId, Identity, Name);

    #endregion
}
