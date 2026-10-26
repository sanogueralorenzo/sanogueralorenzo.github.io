using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Shows the reviewed Space `SourceSpaceId`.
public sealed record ShowImportSpace(Guid SourceSpaceId) : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, _) =>
        flow.Review is { } review ? flow with { Review = review.Showing(SourceSpaceId) } : flow);

    #endregion
}
