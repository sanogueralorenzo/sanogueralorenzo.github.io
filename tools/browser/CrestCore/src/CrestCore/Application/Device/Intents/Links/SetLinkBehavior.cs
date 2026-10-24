using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Turns one on-or-off link preference on or off.
public sealed record SetLinkBehavior(LinkBehavior Behavior, bool IsOn) : LinkIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseLinks(turn.Changes, links => Behavior.Setting(links, IsOn));

    #endregion
}
