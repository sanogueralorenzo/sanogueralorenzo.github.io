using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Chooses where a link from another app opens when no route takes it, and,
/// for a destination that asks for one, the Space it opens in; null keeps the
/// Space chosen before.
public sealed record ChooseExternalLinkDestination(ExternalLinkDestination Destination, Guid? SpaceId) : LinkIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseLinks(turn.Changes, links =>
            links with { Destination = Destination, DestinationSpaceId = SpaceId ?? links.DestinationSpaceId });

    #endregion
}
