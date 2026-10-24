using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Changes exactly one field of a route, so an edit never overwrites another
/// field with a stale copy. Refused with `UnknownLinkRoute`, with
/// `InvalidLinkRouteEdit` unless exactly one field is given, and with
/// `LinkPatternTooLong` past `MaximumPatternLength`.
public sealed record EditLinkRoute(Guid RouteId, bool? IsEnabled, LinkRouteMatch? Match, string? Pattern, Guid? DestinationSpaceId)
    : LinkIntent {
    #region Static Variables

    public const int MaximumPatternLength = 2048;

    #endregion

    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseLinks(turn.Changes, links => links.Editing(this));

    #endregion
}
