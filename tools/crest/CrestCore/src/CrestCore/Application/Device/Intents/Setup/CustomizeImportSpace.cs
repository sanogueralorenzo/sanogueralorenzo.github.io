using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Gives the reviewed Space `SourceSpaceId` the name and look of
/// `Customization`, kept within the ranges every device draws.
public sealed record CustomizeImportSpace(Guid SourceSpaceId, SpaceCustomization Customization) : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) =>
        Device.Editing(flow, review => review.Customizing(SourceSpaceId, Customization, session)));

    #endregion
}
