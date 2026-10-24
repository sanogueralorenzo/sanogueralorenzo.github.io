using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Brings the tab `TabId` of the reviewed Space `SourceSpaceId` in
/// `Placement`, and with it the Space.
public sealed record PlaceImportTab(Guid SourceSpaceId, Guid TabId, TabPlacement Placement) : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) =>
        Device.Editing(flow, review => review.Placing(SourceSpaceId, TabId, Placement, session)));

    #endregion
}
