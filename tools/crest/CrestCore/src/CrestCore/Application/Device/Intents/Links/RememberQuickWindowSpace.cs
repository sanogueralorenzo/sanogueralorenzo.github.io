using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Remembers the Space a Quick Window opened `Url`'s site in, when the
/// preferences remember Spaces by site and the address has a host; otherwise
/// changes nothing.
public sealed record RememberQuickWindowSpace(string Url, Guid SpaceId) : LinkIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseLinks(turn.Changes, links => links.Remembering(Url, SpaceId));

    #endregion
}
