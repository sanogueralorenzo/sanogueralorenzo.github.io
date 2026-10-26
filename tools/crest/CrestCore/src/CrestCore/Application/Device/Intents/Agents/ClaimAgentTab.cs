using CrestCore.Application;

namespace CrestCore.Contracts;

/// The agent connected as `SessionId` uses `TabId` from now on, which shows
/// the person it does and keeps the tab's page loaded while it stays
/// connected. Refused with `AgentTabUnavailable` for a tab no Space it reaches
/// holds, one in a locked Space or one showing one of Crest's own views, and
/// with `AgentTabStopped` for one the person stopped it using.
public sealed record ClaimAgentTab(Guid SessionId, Guid TabId) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ClaimAgentTab(turn.Changes, SessionId, TabId);

    #endregion
}
