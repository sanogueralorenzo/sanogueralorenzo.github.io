using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Brings the reviewed Space `SourceSpaceId` with every tab its destination
/// does not already hold, or leaves it out with all of them.
public sealed record IncludeImportSpace(Guid SourceSpaceId, bool Included) : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) =>
        Device.Editing(flow, review => review.IncludingSpace(SourceSpaceId, Included, session)));

    #endregion
}
