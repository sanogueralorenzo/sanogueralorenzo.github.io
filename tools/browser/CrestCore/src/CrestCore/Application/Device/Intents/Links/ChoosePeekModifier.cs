using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Chooses the key that opens a clicked link in Peek.
public sealed record ChoosePeekModifier(LinkPeekModifier Modifier) : LinkIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseLinks(turn.Changes, links => links with { PeekModifier = Modifier });

    #endregion
}
