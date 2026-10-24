using CrestCore.Application;

namespace CrestCore.Contracts;

/// The browsers the platform found installed, in the order it lists them,
/// which is the order setup imports from them.
public sealed record OfferImportSources(IReadOnlyList<ImportSource> Installed) : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, _) =>
        flow with { Offered = Installed, Selected = [.. Installed.Where(flow.Selected.Contains)] });

    #endregion
}
