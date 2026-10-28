using CrestCore.Application;

namespace CrestCore.Contracts;

/// Lets agents run scripts in a page's own world, or stops them. Agents always
/// read and act on pages from a world of their own.
public sealed record SetAgentScripts(bool RunsScripts) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseAgents(turn.Changes, preferences => preferences with { RunsScripts = RunsScripts });

    #endregion
}
