using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Moves a route `Offset` places among the routes, which match in order. A
/// move past either end changes nothing. Refused with `UnknownLinkRoute`.
public sealed record MoveLinkRoute(Guid RouteId, int Offset) : LinkIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseLinks(turn.Changes, links => links.Moving(this));

    #endregion
}
