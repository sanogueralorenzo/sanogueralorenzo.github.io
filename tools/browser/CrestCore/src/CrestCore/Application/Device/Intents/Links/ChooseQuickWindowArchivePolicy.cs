using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Chooses how long an idle Quick Window lives before it is archived.
public sealed record ChooseQuickWindowArchivePolicy(QuickWindowArchivePolicy Policy) : LinkIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseLinks(turn.Changes, links => links with { ArchivePolicy = Policy });

    #endregion
}
