using CrestCore.Application;

namespace CrestCore.Contracts;

/// The agent connected as `SessionId` asked to be shown as `Name`, in `Color`,
/// as its brand has it. The name keeps only what is safe to show, and the
/// colour is always opaque; either left out keeps what the agent had.
public sealed record IdentifyAgent(Guid SessionId, string? Name, BrandColor? Color) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        var color = Color is { } given
            ? new BrandColor(Math.Clamp(given.Red, 0, 1), Math.Clamp(given.Green, 0, 1), Math.Clamp(given.Blue, 0, 1))
            : null;
        if (color is not null && !(double.IsFinite(color.Red) && double.IsFinite(color.Green) && double.IsFinite(color.Blue)))
            color = null;
        device.ReviseAgentSessions(turn.Changes, sessions => sessions.Identify(SessionId, AgentPreferences.CleanName(Name), color));
    }

    #endregion
}
