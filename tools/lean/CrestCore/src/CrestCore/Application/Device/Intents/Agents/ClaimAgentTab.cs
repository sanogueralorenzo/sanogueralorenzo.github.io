using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record ClaimAgentTab(Guid SessionId, Guid TabId) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ClaimAgentTab(turn.Changes, SessionId, TabId);

    #endregion
}
