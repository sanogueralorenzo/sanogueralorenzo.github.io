using CrestCore.Application;

namespace CrestCore.Contracts;

/// Lets agents use Crest, or stops them; turning agents off disconnects every
/// agent. The Spaces and agents the person chose are kept either way.
public sealed record SetAgents(bool IsOn) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseAgents(turn.Changes, preferences => preferences with { IsOn = IsOn });

    #endregion
}
